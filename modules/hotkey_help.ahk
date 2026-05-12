; ============================================
; 托盘热键帮助模块
; --------------------------------------------
; 这个模块只负责“把当前 main.ahk 实际加载的热键，用新人能看懂的方式展示出来”。
;
; 设计取舍：
; 1) 不解析 hotkeys.ahk 里的注释。注释适合人读，但格式一变解析器就容易坏。
; 2) 不直接展示 AutoHotkey 内置 ListHotkeys。它更像调试窗口，会出现 hook/register 等术语。
; 3) 使用显式注册表。每新增一个热键，就在这里补一条说明，内容完全可控。
; ============================================

; 返回当前已加载热键的显式清单。
; 入参：无。
; 出参：数组；每个元素是 Map，包含 category / key / description。
HotkeyHelpGetEntries() {
    entries := []

    HotkeyHelpAdd(entries, "Codex", "Ctrl+Alt+F12", "打开 Codex 预设菜单，用于切换海豹云 / OpenAI Official / Right Code 等本机配置。")

    HotkeyHelpAdd(entries, "文本处理", "Ctrl+Shift+C", "复制当前选中文本，并删除回车换行；Windows Terminal 中不会启用，避免覆盖终端复制。")
    HotkeyHelpAdd(entries, "文本处理", "Ctrl+Win+C", "复制 QQ/微信聊天文本，清理时间戳、附件噪声，并整理成“昵称: 内容”。")
    HotkeyHelpAdd(entries, "文本处理", "Ctrl+Alt+M", "把剪贴板里的 Markdown 引用式链接展开为行内链接。")

    HotkeyHelpAdd(entries, "Spotify / 媒体", "Ctrl+Alt+Space", "优先控制 Spotify 播放/暂停；Spotify 不在时发送系统媒体播放/暂停键。")
    HotkeyHelpAdd(entries, "Spotify / 媒体", "Ctrl+Alt+Left", "优先控制 Spotify 上一首；Spotify 不在时发送系统上一首键。")
    HotkeyHelpAdd(entries, "Spotify / 媒体", "Ctrl+Alt+Right", "优先控制 Spotify 下一首；Spotify 不在时发送系统下一首键。")
    HotkeyHelpAdd(entries, "Spotify / 媒体", "Ctrl+X 后按 Space", "在 Ctrl+X 短事务中触发 Spotify 分支；没有按 Space 时回落为普通剪切。")

    HotkeyHelpAdd(entries, "鼠标", "鼠标前进键", "发送 Ctrl+C，相当于复制。")
    HotkeyHelpAdd(entries, "鼠标", "鼠标后退键", "发送 Ctrl+V，相当于粘贴。")

    HotkeyHelpAdd(entries, "沙盒中转", "Ctrl+Alt+C", "从资源管理器当前选中项创建微信/QQ 沙盒中转任务。")
    HotkeyHelpAdd(entries, "沙盒中转", "Ctrl+Alt+V", "单文件时粘贴到微信/QQ；多文件时二次触发清理；无任务时手动清理残留。")

    HotkeyHelpAdd(entries, "窗口 / 系统", "Left Ctrl+Space", "发送 Enter；但 Ctrl+X+Space 的 Spotify 分支优先。")
    HotkeyHelpAdd(entries, "窗口 / 系统", "Left Alt 抬起", "触发现有窗口切换辅助逻辑。")
    HotkeyHelpAdd(entries, "窗口 / 系统", "Win+Alt+D", "尝试结束 WPS / Kingsoft 相关进程。")

    return entries
}

; 向热键清单追加一条记录。
; 入参：
; - entries：数组，调用方传入并由本函数追加。
; - category：分组名。
; - key：热键显示文本。
; - description：用途说明。
; 出参：无，直接修改 entries。
HotkeyHelpAdd(entries, category, key, description) {
    entries.Push(Map(
        "category", category,
        "key", key,
        "description", description
    ))
}

; 生成适合显示/复制的纯文本热键帮助。
; 入参：无。
; 出参：多行字符串。
HotkeyHelpBuildDisplayText() {
    entries := HotkeyHelpGetEntries()
    text := "AHK 当前已加载热键`r`n"
        . "生成来源：显式注册表，不解析注释；只列 main.ahk 当前加载的功能。`r`n"
        . "========================================`r`n"

    currentCategory := ""
    for _, entry in entries {
        category := entry["category"]
        if (category != currentCategory) {
            if (currentCategory != "") {
                text .= "`r`n"
            }
            text .= "[" category "]`r`n"
            currentCategory := category
        }
        text .= "  " entry["key"] " - " entry["description"] "`r`n"
    }

    return RTrim(text, "`r`n")
}

; 打开热键帮助窗口。
; 入参：无。
; 出参：无。
; 说明：
; - 使用 AHK 自带 Gui，不依赖浏览器或外部编辑器。
; - 窗口内文本只读，可滚动；“复制列表”会写入剪贴板。
HotkeyHelpShowWindow(*) {
    static helpGui := 0

    if IsObject(helpGui) {
        try helpGui.Destroy()
    }

    helpGui := Gui("+Resize", "AHK 当前热键")
    helpGui.SetFont("s10", "Microsoft YaHei UI")
    helpGui.Add("Text", "xm ym", "当前 main.ahk 已加载热键")
    helpGui.Add("Edit", "xm y+8 w780 h520 ReadOnly -Wrap", HotkeyHelpBuildDisplayText())

    copyButton := helpGui.Add("Button", "xm y+10 w110", "复制列表")
    copyButton.OnEvent("Click", HotkeyHelpCopyList)

    closeButton := helpGui.Add("Button", "x+8 yp w80", "关闭")
    closeButton.OnEvent("Click", (*) => helpGui.Destroy())

    helpGui.Show()
}

; 把当前热键帮助文本复制到剪贴板。
; 入参：事件参数由 Gui 自动传入，本函数不使用。
; 出参：无。
HotkeyHelpCopyList(*) {
    A_Clipboard := HotkeyHelpBuildDisplayText()
    Toast("已复制热键列表")
}

; 初始化系统托盘菜单。
; 入参：无。
; 出参：无。
; 说明：
; - A_TrayMenu 是 AutoHotkey v2 官方托盘菜单对象。
; - 这里保留标准 Reload / Exit 等菜单项，避免破坏 AHK 默认操作习惯。
AhkToolkitInitializeTrayMenu() {
    CodexProfilesEnsureLayout()

    A_TrayMenu.Add()
    A_TrayMenu.Add("查看热键", HotkeyHelpShowWindow)
    A_TrayMenu.Add("Codex 预设", CodexProfilesBuildTrayMenu())
    A_TrayMenu.Add("打开 Codex 预设目录", CodexProfilesOpenRoot)
    A_TrayMenu.Add("校验 Codex 预设", CodexProfilesValidateAllFromTray)
    A_TrayMenu.Add()
    A_TrayMenu.AddStandard()
}

