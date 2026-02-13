; ============================================
; 聊天消息复制清洗模块（QQ/微信文本）
; --------------------------------------------
; 这个模块专门负责“聊天文本清洗”完整流程，供 hotkeys.ahk 以短入口调用：
; 1) 触发 Ctrl+C 复制当前选中文本。
; 2) 解析“昵称 + 时间 + 内容”的聊天导出文本结构。
; 3) 去掉时间戳，合并消息内部换行，整理为“一行一条：昵称: 内容”。
; 4) 每次执行时都重新读取 TOML 昵称映射文件，实现“改配置立即生效（无需 Reload）”。
; 5) 成功后把清洗结果写回剪贴板，并用 ToolTip 提示“共处理多少条消息”。
;
; 设计取舍说明：
; - 解析规则优先覆盖你当前 QQ 复制样式：`昵称: 02-13 19:26:29` + 下一行内容。
; - 若消息正文本来有多行，会合并成单行，便于后续粘贴到大模型或笔记工具。
; - TOML 仅实现“昵称映射”所需最小子集（[names] + key=value），简单直观、便于维护。
; ============================================

; 对外入口：复制并清洗聊天消息
; 入参：无（内部自动发送 Ctrl+C）
; 返回：true=成功，false=失败（失败时会恢复原剪贴板）
ChatCopyNormalizeMessages() {
    clipBackup := ClipboardAll()                          ; 先备份完整剪贴板，失败时可回滚
    handled := false                                      ; 标记本次是否成功处理，供 finally 判定是否恢复
    configPath := ChatAliasEnsureConfigFile()             ; 确保 TOML 配置文件存在（首次自动生成示例）

    try {
        A_Clipboard := ""                                 ; 先清空剪贴板，避免误读旧内容
        Sleep(40)                                         ; 给系统一个极短缓冲时间，提升稳定性
        Send("^c")                                        ; 触发当前窗口复制

        if !ClipWait(1) {                                 ; 等待最多 1 秒拿到复制结果
            Toast("❌ 复制超时：未获取到聊天文本")
            return false
        }

        rawText := A_Clipboard                            ; 读取本次复制到的原始文本
        if (Trim(rawText, " `t`r`n") = "") {             ; 空文本直接给提示，避免继续解析
            Toast("❌ 未检测到可清洗的文本")
            return false
        }

        aliasMap := ChatAliasLoadMap(configPath)          ; 每次执行都从 TOML 读取映射，实现热更新
        cleanedLines := ChatParseChatMessages(rawText, aliasMap) ; 执行核心解析与清洗

        if (cleanedLines.Length = 0) {                    ; 没匹配到消息头时，不覆盖原剪贴板
            Toast("⚠️ 未识别到聊天消息结构，已保留原始复制内容")
            return false
        }

        outputText := ChatJoinArray(cleanedLines, "`n")   ; 按“每行一条消息”拼接
        A_Clipboard := outputText                          ; 把清洗结果写回剪贴板
        handled := true                                    ; 标记成功，finally 不再回滚
        Toast("✅ 已复制并清洗 " cleanedLines.Length " 条消息")
        return true
    } catch as err {
        Toast("❌ 清洗失败：" err.Message)                 ; 捕获异常并提示关键信息
        return false
    } finally {
        if !handled {                                      ; 仅失败时恢复旧剪贴板，减少对日常流程影响
            A_Clipboard := clipBackup
        }
    }
}

; 解析聊天文本，输出“昵称: 内容”行数组
; 入参：
; - rawText: 复制得到的原始全文字符串
; - aliasMap: 昵称映射 Map，key=原昵称，value=替换后昵称
; 出参：
; - lines: 数组，每个元素是一条格式化后的消息行
ChatParseChatMessages(rawText, aliasMap) {
    lines := []                                            ; 输出数组：每项是一条“昵称: 内容”
    normalizedText := StrReplace(rawText, "`r", "")       ; 统一换行符，便于逐行遍历
    rawLines := StrSplit(normalizedText, "`n")            ; 按行拆分原始文本

    currentName := ""                                      ; 当前消息所属昵称
    currentBodyParts := []                                 ; 当前消息正文分片（用于合并多行）

    for _, line in rawLines {                              ; 顺序扫描每一行，遇到新消息头就提交上一条
        trimmedLine := Trim(line, " `t")                  ; 去掉首尾空白，降低格式波动影响

        headerName := ""                                   ; 存放本行匹配到的消息头昵称
        if ChatTryParseHeaderLine(trimmedLine, &headerName) {
            ChatPushMessage(lines, currentName, currentBodyParts)   ; 新消息开始前，先提交上一条
            currentName := ChatApplyAlias(headerName, aliasMap)      ; 对昵称执行映射替换
            currentBodyParts := []                                   ; 为新消息初始化正文数组
            continue
        }

        if (currentName = "") {                           ; 尚未进入任何消息体时，忽略噪声行
            continue
        }
        if (trimmedLine = "") {                           ; 空行仅作分隔，不写入正文
            continue
        }

        currentBodyParts.Push(trimmedLine)                ; 把正文行追加到当前消息缓存
    }

    ChatPushMessage(lines, currentName, currentBodyParts) ; 文件结束时补交最后一条消息
    return lines
}

; 尝试解析“消息头行”（昵称 + 时间）
; 典型输入：`酥皮小鱼: 02-13 19:26:29`
; 入参：
; - line: 当前行文本
; - &speakerName: 输出参数，解析成功后写入昵称
; 返回：
; - true=该行是消息头，false=普通正文行
ChatTryParseHeaderLine(line, &speakerName) {
    static headerPattern := "^\s*(.+?)\s*[:：]\s*(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}|\d{1,2}月\d{1,2}日)\s+\d{1,2}:\d{2}(?::\d{2})?\s*$"

    speakerName := ""                                      ; 先清空输出参数，避免复用旧值
    if !RegExMatch(line, headerPattern, &m) {              ; 正则不匹配即说明不是消息头
        return false
    }

    parsedName := Trim(m[1], " `t")                        ; 取出昵称并去空白
    if (parsedName = "") {                                 ; 兜底：空昵称不算有效消息头
        return false
    }

    speakerName := parsedName                              ; 回写输出参数给调用方
    return true
}

; 把“当前正在累积的一条消息”压入输出数组
; 入参：
; - lines: 输出数组引用
; - name: 当前消息昵称（已完成映射）
; - bodyParts: 当前消息正文分片数组
; 说明：
; - 会把正文中多行合并为空格分隔的单行；
; - 会压缩多余连续空白，保证输出整洁。
ChatPushMessage(lines, name, bodyParts) {
    if (name = "") {                                       ; 没有昵称说明尚未开始有效消息，直接跳过
        return
    }

    mergedBody := ChatJoinArray(bodyParts, " ")            ; 多行正文合并成一行（以空格分隔）
    mergedBody := Trim(RegExReplace(mergedBody, "\s+"," ")) ; 压缩空白字符，避免出现连续空格
    if (mergedBody = "") {                                 ; 若正文为空，保留空占位，防止语义丢失
        mergedBody := "[空消息]"
    }

    lines.Push(name ": " mergedBody)                       ; 输出统一格式：昵称: 内容
}

; 应用昵称映射
; 入参：
; - sourceName: 原始昵称
; - aliasMap: 映射表
; 出参：
; - 若命中映射，返回映射值；否则返回原昵称
ChatApplyAlias(sourceName, aliasMap) {
    if aliasMap.Has(sourceName) {                          ; 命中映射时替换成目标昵称
        return aliasMap[sourceName]
    }
    return sourceName                                      ; 未命中则保持原值
}

; 确保昵称映射配置文件存在（首次会生成示例）
; 返回：配置文件绝对路径
ChatAliasEnsureConfigFile() {
    configDir := A_ScriptDir "\config"                     ; 配置目录统一放在项目根的 config
    configPath := configDir "\chat_name_alias.toml"        ; 昵称映射配置文件路径

    if !DirExist(configDir) {                              ; 配置目录不存在就创建
        DirCreate(configDir)
    }

    if !FileExist(configPath) {                            ; 首次不存在时写入教学向示例
        ; 这里不用“多段引号拼接”，而是先按“逐行数组”组织再 Join，
        ; 这样语法更直观，且能避免部分编辑器把复杂引号误判为 v1 语法。
        exampleLines := [
            "# ===========================================",          ; 配置头注释：分隔线（TOML 标准注释用 #）
            "# 聊天昵称映射配置（TOML）",                             ; 配置头注释：文件用途
            "# 修改后无需 Reload 脚本：下次按 Ctrl+Win+C 会自动重新读取", ; 配置头注释：热更新说明
            "# 使用方式：在 [names] 下写 原昵称 = 替换昵称",           ; 配置头注释：写法说明
            "# ===========================================",          ; 配置头注释：分隔线
            "",                                                     ; 空行：增强可读性
            "[names]",                                              ; TOML 分节：昵称映射
            "`"酥皮小鱼`" = `"AAA`"",                               ; 示例映射：原昵称 -> 目标昵称
            "`"张三`" = `"产品同学`""                               ; 示例映射：原昵称 -> 目标昵称
        ]
        example := ChatJoinArray(exampleLines, "`n")                ; 用 LF 拼接成完整 TOML 文本
        FileAppend(example, configPath, "UTF-8")           ; 以 UTF-8 写入，兼容中文昵称
        Toast("ℹ️ 已创建昵称映射配置：config\\chat_name_alias.toml")
    }

    return configPath
}

; 读取 TOML 昵称映射
; 支持最小格式：
; [names]
; "原昵称" = "新昵称"
; 返回：Map
ChatAliasLoadMap(configPath) {
    aliasMap := Map()                                       ; 输出映射表
    if !FileExist(configPath) {                             ; 文件不存在时返回空映射
        return aliasMap
    }

    fileText := FileRead(configPath, "UTF-8")              ; 读取 TOML 原文
    lines := StrSplit(StrReplace(fileText, "`r", ""), "`n") ; 统一换行后逐行处理
    inNamesSection := false                                 ; 仅解析 [names] 分节

    for _, rawLine in lines {
        line := ChatStripTomlInlineComment(rawLine)         ; 先去掉行内注释（保留引号内内容）
        line := Trim(line, " `t")                          ; 再清理首尾空白
        if (line = "") {                                   ; 空行直接跳过
            continue
        }

        if RegExMatch(line, "^\[(.+)\]$", &sec) {         ; 识别 TOML 分节
            sectionName := StrLower(Trim(sec[1], " `t"))
            inNamesSection := (sectionName = "names")      ; 仅 [names] 内的键值参与映射
            continue
        }

        if !inNamesSection {                               ; 非 [names] 分节内容忽略
            continue
        }

        if !RegExMatch(line, "^(.*?)\s*=\s*(.*)$", &kv) { ; 非 key=value 格式忽略
            continue
        }

        sourceName := ChatParseTomlToken(kv[1])            ; 解析左侧 key（支持带引号）
        targetName := ChatParseTomlToken(kv[2])            ; 解析右侧 value（支持带引号）
        if (sourceName = "") {                             ; 空 key 无意义，直接跳过
            continue
        }
        aliasMap[sourceName] := targetName                 ; 写入或覆盖映射（后者优先）
    }

    return aliasMap
}

; 去掉 TOML 行内注释（# 或 ;），但保留引号字符串内部内容
; 例如： "A#B" = "C;D" # 注释  ->  "A#B" = "C;D"
ChatStripTomlInlineComment(line) {
    static CHAR_QUOTE := Chr(34)                            ; 双引号字符（"）
    static CHAR_BACKSLASH := Chr(92)                        ; 反斜杠字符（\）
    inQuote := false                                        ; 是否当前位于双引号字符串内部
    escaped := false                                        ; 上一个字符是否为转义符

    Loop Parse, line {
        ch := A_LoopField                                   ; 当前字符
        idx := A_Index                                      ; 当前字符位置（1-based）

        if escaped {                                        ; 转义后的字符直接吞掉并复位状态
            escaped := false
            continue
        }
        if (ch = CHAR_BACKSLASH) {                          ; 反斜杠用于转义下一个字符
            escaped := inQuote                              ; 仅在引号内部才按转义处理
            continue
        }
        if (ch = CHAR_QUOTE) {                              ; 遇到双引号时切换“是否在字符串中”
            inQuote := !inQuote
            continue
        }
        if !inQuote && (ch = "#" || ch = ";") {           ; 引号外遇到注释符即截断
            return SubStr(line, 1, idx - 1)
        }
    }

    return line                                             ; 没有注释符时原样返回
}

; 解析 TOML token（支持 "xxx"、'xxx'、裸字符串）
; 说明：为避免过度复杂，这里只实现昵称映射所需最小能力。
ChatParseTomlToken(token) {
    static CHAR_QUOTE := Chr(34)                            ; 双引号字符（"）
    static CHAR_APOS := "'"                                 ; 单引号字符（'）
    static CHAR_BACKSLASH := Chr(92)                        ; 反斜杠字符（\）
    text := Trim(token, " `t")                              ; 先做基础去空白
    if (text = "") {
        return ""
    }

    first := SubStr(text, 1, 1)                             ; 读取首字符用于判断引号类型
    last := SubStr(text, -1)                                ; 读取尾字符用于闭合校验

    if (first = CHAR_QUOTE && last = CHAR_QUOTE) {          ; 双引号字符串：支持简单转义
        inner := SubStr(text, 2, StrLen(text) - 2)
        inner := StrReplace(inner, CHAR_BACKSLASH . CHAR_QUOTE, CHAR_QUOTE)   ; 还原 \" -> "
        inner := StrReplace(inner, CHAR_BACKSLASH . CHAR_BACKSLASH, CHAR_BACKSLASH) ; 还原 \\ -> \
        return inner
    }
    if (first = CHAR_APOS && last = CHAR_APOS) {            ; 单引号字符串：按字面量处理
        return SubStr(text, 2, StrLen(text) - 2)
    }

    return text                                             ; 裸值直接返回
}

; 通用数组拼接工具（避免依赖运行环境是否提供 Array.Join）
; 入参：
; - arr: 字符串数组
; - sep: 分隔符
; 返回：拼接后的字符串
ChatJoinArray(arr, sep) {
    if (arr.Length = 0) {                                  ; 空数组直接返回空串
        return ""
    }

    out := ""                                              ; 初始化输出缓存
    for idx, item in arr {                                 ; 顺序拼接，避免末尾多余分隔符
        if (idx > 1) {
            out .= sep
        }
        out .= item
    }
    return out
}
