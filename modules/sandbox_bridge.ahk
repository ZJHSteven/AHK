; ============================================
; 沙盒聊天软件文件中转模块（微信/QQ）
; --------------------------------------------
; 这个模块专门负责“文件中转”的完整生命周期：
; 1) 从资源管理器抓取当前选中的文件/文件夹（支持多选）。
; 2) 将选中项复制到各个沙盒下载目录下的统一中转子目录。
; 3) 单文件模式下：在微信/QQ 窗口里一键粘贴，并延时自动清理中转文件。
; 4) 多文件模式下：用户手动发送后，快速二次触发热键执行清理。
; 5) 新任务开始前会先清理上一轮残留，保证“只维护一个任务状态”。
;
; 设计取舍说明：
; - 使用固定中转子目录 `__AHK_Transit__`，避免误删下载目录里的普通文件。
; - 使用 CF_HDROP 写入剪贴板，让聊天软件把路径识别为“文件粘贴”而不是纯文本。
; - 粘贴动作仅在微信/QQ窗口触发；清理动作允许任意窗口触发，减少切窗成本。
; ============================================

; ---------- 配置区：你后续扩展其他沙盒时，只要在这里增加目标即可 ----------
global g_SandboxBridgeTargets := Map(
    "wechat", "D:\Sandboxie\WeChat\user\current\Downloads",  ; 微信沙盒下载目录（根）
    "qq", "D:\Sandboxie\QQ\user\current\Downloads"           ; QQ 沙盒下载目录（根）
)

global g_SandboxBridgeTransitFolderName := "__AHK_Transit__" ; 中转子目录名称（固定，便于安全清理）
global g_SandboxBridgeAutoCleanupMs := 90000                 ; 单文件自动清理延时：90 秒（约 1.5 分钟）
global g_SandboxBridgeDoubleTapMs := 2500                    ; 多文件模式下“双击清理”时间窗：2.5 秒

; ---------- 状态区：单任务状态机 ----------
global g_SandboxBridgeState := {                              ; 用对象保存一次任务全量状态
    active: false,                                            ; 当前是否存在有效中转任务
    sourceItems: [],                                          ; 本轮源项列表（选中的原始路径）
    stagedByTarget: Map(),                                    ; 各目标下复制后的路径列表：key -> [path...]
    stagedAll: [],                                            ; 方便统一清理的扁平路径列表
    singleFileMode: false,                                    ; 是否“单文件任务”
    singleFileByTarget: Map(),                                ; 单文件模式下各目标对应的唯一文件路径
    lastCleanupTapTick: 0                                     ; 记录上次按 Ctrl+Alt+V 的时刻，用于双击清理
}

; 对外入口函数：执行“中转复制”（通常由热键调用）
; 入参：无（内部会主动读取当前选中项）
; 返回：true=成功创建任务，false=失败
SandboxBridgeStageFromSelection() {
    global g_SandboxBridgeState  ; 读取和写入全局任务状态

    SetTimer(SandboxBridgeAutoCleanup, 0)  ; 取消可能残留的自动清理定时器，避免旧任务定时器误触发

    ; 新任务开始前先清理旧任务，满足“单任务、状态重置”的需求。
    if g_SandboxBridgeState.active {
        SandboxBridgeCleanupStagedFiles(false)
    }

    selectedItems := SandboxBridgeCaptureSelectedPaths()  ; 读取当前选中项（文件/目录/多选）
    if (selectedItems.Length = 0) {
        Toast("❌ 未检测到可用选中项，请先在资源管理器中选中文件/文件夹")
        return false
    }

    SandboxBridgeResetState()                ; 初始化新任务状态，避免旧字段干扰
    g_SandboxBridgeState.sourceItems := selectedItems  ; 记录源项列表，便于后续排查和提示

    copiedCount := 0                         ; 统计成功复制条数（跨目标累计）
    failedCount := 0                         ; 统计失败复制条数（跨目标累计）

    ; 双层循环：把每个选中项复制到每个目标沙盒目录。
    for targetKey, targetRoot in g_SandboxBridgeTargets {
        transitDir := SandboxBridgeGetTransitDir(targetRoot)  ; 目标根目录 + 固定中转子目录
        if !DirExist(transitDir) {
            try DirCreate(transitDir)                         ; 缺目录就创建，减少首次使用失败
            catch {
                failedCount += selectedItems.Length           ; 目标目录不可用，本目标全部记失败
                continue                                      ; 跳过该目标，避免阻塞其他目标
            }
        }

        g_SandboxBridgeState.stagedByTarget[targetKey] := [] ; 预先初始化该目标的列表

        for _, sourcePath in selectedItems {
            itemName := SandboxBridgeGetItemName(sourcePath)  ; 提取项名（兼容目录末尾斜杠）
            stagedPath := transitDir "\" itemName             ; 复制后的完整落地路径

            ; 先清掉同名旧中转项（只在中转目录内操作，避免误删普通下载文件）。
            oldAttr := FileExist(stagedPath)
            if oldAttr {
                try {
                    if InStr(oldAttr, "D")
                        DirDelete(stagedPath, 1)              ; 目录递归删除
                    else
                        FileDelete(stagedPath)                ; 文件直接删除
                } catch {
                    ; 同名旧文件删不掉时，后续复制大概率也会失败，让复制分支去记录失败即可。
                }
            }

            ; 根据源类型选择 DirCopy / FileCopy。
            try {
                if SandboxBridgeIsDirectory(sourcePath)
                    DirCopy(sourcePath, stagedPath, true)     ; 目录复制（允许覆盖）
                else
                    FileCopy(sourcePath, stagedPath, true)    ; 文件复制（允许覆盖）

                g_SandboxBridgeState.stagedByTarget[targetKey].Push(stagedPath)  ; 记录目标维度路径
                g_SandboxBridgeState.stagedAll.Push(stagedPath)                   ; 记录扁平路径用于清理
                copiedCount += 1                                                  ; 成功计数
            } catch {
                failedCount += 1                                                  ; 失败计数
            }
        }
    }

    if (copiedCount = 0) {
        SandboxBridgeResetState()  ; 全部失败时直接回到空状态
        Toast("❌ 中转失败：未成功复制任何文件，请检查沙盒目录是否可访问")
        return false
    }

    ; 单文件模式定义：仅选择了 1 项，且该项不是目录。
    g_SandboxBridgeState.singleFileMode := (selectedItems.Length = 1 && !SandboxBridgeIsDirectory(selectedItems[1]))
    if g_SandboxBridgeState.singleFileMode {
        for targetKey, stagedList in g_SandboxBridgeState.stagedByTarget {
            if (stagedList.Length >= 1) {
                g_SandboxBridgeState.singleFileByTarget[targetKey] := stagedList[1]  ; 每个目标取唯一文件
            }
        }
    }

    g_SandboxBridgeState.active := true  ; 标记任务生效，后续粘贴/清理流程才可运行

    ; 根据模式给出明确提示，帮助你记住下一步怎么按。
    if g_SandboxBridgeState.singleFileMode {
        Toast("✅ 中转完成（单文件）。切到微信/QQ 后按 Ctrl+Alt+V 一键粘贴")
    } else {
        Toast("✅ 中转完成（多项）。发送完成后快速按两次 Ctrl+Alt+V 清理")
    }

    if (failedCount > 0) {
        Toast("⚠️ 部分项复制失败（失败 " failedCount " 条），可先试发成功项")
    }
    return true
}

; 对外入口函数：执行“粘贴或清理”（通常由热键调用）
; 逻辑：
; - 先统一判断“双击清理”，确保清理逻辑不会被粘贴逻辑抢占。
; - 单文件模式：第一次按=粘贴，2.5 秒内第二次按=立即清理（否则走90秒自动清理）。
; - 多文件模式：第一次按=进入待清理状态，2.5 秒内第二次按=执行清理（任意窗口都可按）。
SandboxBridgePasteOrCleanup() {
    global g_SandboxBridgeState, g_SandboxBridgeAutoCleanupMs, g_SandboxBridgeDoubleTapMs

    if !g_SandboxBridgeState.active {
        Toast("ℹ️ 当前没有中转任务，请先按 Ctrl+Alt+C 执行中转复制")
        return false
    }

    nowTick := A_TickCount  ; 读取当前时间戳，用于双击窗口判定

    ; 先判断是否为“二次按键”：
    ; 只要在阈值内再次触发，就优先执行清理，避免被粘贴分支拦截。
    if (g_SandboxBridgeState.lastCleanupTapTick > 0
        && (nowTick - g_SandboxBridgeState.lastCleanupTapTick <= g_SandboxBridgeDoubleTapMs)) {
        SandboxBridgeCleanupStagedFiles(true)
        return true
    }

    ; 超过双击时间窗后，清空旧时间戳，避免后续误判成二次按键。
    g_SandboxBridgeState.lastCleanupTapTick := 0

    if g_SandboxBridgeState.singleFileMode {
        targetKey := SandboxBridgeDetectActiveTarget()  ; 单文件要“自动粘贴”，所以仍需校验当前窗口
        if (targetKey = "") {
            Toast("❌ 请先把焦点切到微信或 QQ 聊天窗口")
            return false
        }

        if !g_SandboxBridgeState.singleFileByTarget.Has(targetKey) {
            Toast("❌ 未找到当前窗口对应的中转文件，请重新执行中转复制")
            return false
        }

        stagedFile := g_SandboxBridgeState.singleFileByTarget[targetKey]  ; 当前目标对应的中转文件
        if !FileExist(stagedFile) {
            Toast("❌ 中转文件不存在，可能已被删除，请重新执行中转复制")
            return false
        }

        if !SandboxBridgeSetClipboardFiles([stagedFile]) {                ; 把“文件路径”写为 CF_HDROP
            Toast("❌ 设置文件剪贴板失败，未执行粘贴")
            return false
        }

        Send("^v")                                                         ; 在聊天输入框执行文件粘贴
        SetTimer(SandboxBridgeAutoCleanup, 0)                              ; 先取消旧定时器，防止重复计时
        SetTimer(SandboxBridgeAutoCleanup, -g_SandboxBridgeAutoCleanupMs)  ; 设置一次性自动清理定时器
        g_SandboxBridgeState.lastCleanupTapTick := nowTick                 ; 记录“第一次按键”时间，允许你二次按立即清理
        Toast("📎 已触发粘贴。2.5 秒内再按一次可立即清理；不按则约 90 秒后自动清理")
        return true
    }

    ; 多文件/目录模式：
    ; 首次触发时只“记时间+提示”，不要求当前窗口必须是微信/QQ。
    g_SandboxBridgeState.lastCleanupTapTick := nowTick                    ; 记录第一次按键时间，等待二次确认
    Toast("🧹 多文件模式：发送完成后 2.5 秒内再按一次 Ctrl+Alt+V 即可清理（任意窗口可按）")
    return true
}

; 自动清理回调：供 SetTimer 一次性触发
SandboxBridgeAutoCleanup() {
    global g_SandboxBridgeState

    if !g_SandboxBridgeState.active {
        return  ; 没有任务时无需清理
    }
    SandboxBridgeCleanupStagedFiles(true)  ; 定时触发也走统一清理逻辑
}

; 统一清理函数：删除当前任务复制出来的所有中转文件/目录，并重置状态
; 入参：showToast=true 时弹提示，false 时静默（用于新任务覆盖旧任务）
SandboxBridgeCleanupStagedFiles(showToast := true) {
    global g_SandboxBridgeState

    SetTimer(SandboxBridgeAutoCleanup, 0)  ; 清理时先停掉定时器，防止并发重入

    deletedCount := 0
    failedCount := 0

    for _, stagedPath in g_SandboxBridgeState.stagedAll {
        attr := FileExist(stagedPath)
        if !attr {
            continue                        ; 已不存在就视为无需处理
        }

        try {
            if InStr(attr, "D")
                DirDelete(stagedPath, 1)   ; 删除目录（递归）
            else
                FileDelete(stagedPath)     ; 删除文件
            deletedCount += 1
        } catch {
            failedCount += 1
        }
    }

    SandboxBridgeResetState()              ; 无论成败都重置状态，满足“只维护一次任务”

    if showToast {
        if (failedCount = 0)
            Toast("✅ 中转清理完成，共处理 " deletedCount " 项")
        else
            Toast("⚠️ 清理结束：成功 " deletedCount " 项，失败 " failedCount " 项")
    }
}

; 抓取当前选中文件/目录列表（通过 Explorer 的 Ctrl+C 结果读取）
; 注意：本函数会临时占用剪贴板，但会在 finally 中恢复原剪贴板。
SandboxBridgeCaptureSelectedPaths() {
    selected := []                                ; 返回值：路径数组
    dedup := Map()                                ; 去重，防止重复路径
    clipBackup := ClipboardAll()                  ; 完整备份当前剪贴板（含二进制格式）

    try {
        A_Clipboard := ""                         ; 清空后再触发复制，便于判断是否拿到新内容
        Sleep(40)                                 ; 给系统一点时间完成剪贴板更新
        Send("^c")                                ; 向当前窗口发送复制（资源管理器中会复制选中项）

        if !ClipWait(0.8) {
            return selected                       ; 超时时返回空数组，由上层提示
        }

        ; A_Clipboard 在文件复制场景下会是多行路径文本，逐行解析即可。
        for _, rawLine in StrSplit(A_Clipboard, "`n", "`r") {
            path := Trim(rawLine, " `t`r`n")
            if (path = "" || dedup.Has(path)) {
                continue
            }
            if FileExist(path) {                  ; 仅接收真实存在的文件系统路径
                selected.Push(path)
                dedup[path] := true
            }
        }
    } finally {
        A_Clipboard := clipBackup                 ; 还原原剪贴板，避免影响你的日常复制流程
    }

    return selected
}

; 重置状态对象：用于“任务初始化”和“清理完成后归零”
SandboxBridgeResetState() {
    global g_SandboxBridgeState

    g_SandboxBridgeState.active := false
    g_SandboxBridgeState.sourceItems := []
    g_SandboxBridgeState.stagedByTarget := Map()
    g_SandboxBridgeState.stagedAll := []
    g_SandboxBridgeState.singleFileMode := false
    g_SandboxBridgeState.singleFileByTarget := Map()
    g_SandboxBridgeState.lastCleanupTapTick := 0
}

; 判断当前前台窗口是否属于微信/QQ，并返回目标 key
; 返回：wechat / qq / ""
SandboxBridgeDetectActiveTarget() {
    exe := ""
    title := ""

    try exe := StrLower(WinGetProcessName("A"))   ; 优先按进程名判断，更稳定
    try title := StrLower(WinGetTitle("A"))       ; 兜底按标题关键字判断

    if (exe = "wechat.exe" || InStr(title, "wechat") || InStr(title, "微信"))
        return "wechat"
    if (exe = "qq.exe" || InStr(title, "qq"))
        return "qq"
    return ""
}

; 把一个或多个文件路径写入剪贴板为 CF_HDROP（文件拖放格式）
; 这样聊天软件收到的是“文件粘贴”而不是文本路径。
; 入参：filePaths 为路径数组，要求每个路径必须存在
; 返回：true=成功，false=失败
SandboxBridgeSetClipboardFiles(filePaths) {
    static CF_HDROP := 0x000F
    static GMEM_MOVEABLE := 0x0002
    static GMEM_ZEROINIT := 0x0040
    static DROPFILES_SIZE := 20                   ; DROPFILES 结构体固定大小（字节）

    if (filePaths.Length = 0) {
        return false
    }

    utf16PathBuffers := []                        ; 保存每个路径的 UTF-16 缓冲区
    pathBytesTotal := 0                           ; 所有路径二进制总长度（含每段结尾 \0）

    for _, filePath in filePaths {
        if !FileExist(filePath) {
            return false                          ; 任何一个路径不存在都直接失败
        }
        chars := StrPut(filePath, "UTF-16")       ; 包含结尾 \0 的字符数
        pathBuf := Buffer(chars * 2, 0)           ; UTF-16 每字符 2 字节
        StrPut(filePath, pathBuf, "UTF-16")       ; 写入二进制路径
        utf16PathBuffers.Push(pathBuf)
        pathBytesTotal += pathBuf.Size
    }

    totalBytes := DROPFILES_SIZE + pathBytesTotal + 2  ; 额外 +2 字节用于双 \0 终止
    hGlobal := DllCall("GlobalAlloc", "UInt", GMEM_MOVEABLE | GMEM_ZEROINIT, "UPtr", totalBytes, "Ptr")
    if !hGlobal {
        return false
    }

    pData := DllCall("GlobalLock", "Ptr", hGlobal, "Ptr")
    if !pData {
        DllCall("GlobalFree", "Ptr", hGlobal)
        return false
    }

    ; 写 DROPFILES 头：pFiles=20，fWide=1（Unicode）。
    NumPut("UInt", DROPFILES_SIZE, pData, 0)
    NumPut("Int", 0, pData, 4)
    NumPut("Int", 0, pData, 8)
    NumPut("Int", 0, pData, 12)
    NumPut("Int", 1, pData, 16)

    ; 依次拼接 UTF-16 路径块。
    offset := DROPFILES_SIZE
    for _, pathBuf in utf16PathBuffers {
        DllCall("RtlMoveMemory", "Ptr", pData + offset, "Ptr", pathBuf.Ptr, "UPtr", pathBuf.Size)
        offset += pathBuf.Size
    }
    NumPut("UShort", 0, pData, offset)            ; 末尾补一个 \0，形成双 \0

    DllCall("GlobalUnlock", "Ptr", hGlobal)

    if !DllCall("OpenClipboard", "Ptr", 0) {
        DllCall("GlobalFree", "Ptr", hGlobal)
        return false
    }

    DllCall("EmptyClipboard")
    if !DllCall("SetClipboardData", "UInt", CF_HDROP, "Ptr", hGlobal, "Ptr") {
        DllCall("CloseClipboard")
        DllCall("GlobalFree", "Ptr", hGlobal)
        return false
    }

    DllCall("CloseClipboard")                     ; 成功后内存所有权转交系统，不再手动释放
    return true
}

; 工具：判断路径是否目录
SandboxBridgeIsDirectory(path) {
    return InStr(FileExist(path), "D")
}

; 工具：提取文件名/目录名（兼容目录末尾可能带斜杠）
SandboxBridgeGetItemName(path) {
    cleanPath := RegExReplace(path, "[\\/]+$")
    SplitPath(cleanPath, &name)
    return name
}

; 工具：把“目标根目录”转换成“中转子目录”
SandboxBridgeGetTransitDir(targetRoot) {
    global g_SandboxBridgeTransitFolderName
    return targetRoot "\" g_SandboxBridgeTransitFolderName
}

; 脚本加载时先做一次归零，保证初始状态可预测
SandboxBridgeResetState()
