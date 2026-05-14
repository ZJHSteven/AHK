#Requires AutoHotkey v2.0
; ============================================
; 热键帮助模块测试
; --------------------------------------------
; 这个测试只检查显式注册表的内容，不打开真实 Gui。
; ============================================

#Include ..\modules\utils.ahk
#Include ..\modules\codex_profile_switcher.ahk
#Include ..\modules\hotkey_help.ahk

global g_TestPassCount := 0

try {
    HotkeyHelpRunAllTests()
    FileAppend("OK: " g_TestPassCount " tests passed.`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " err.Message "`n", "*", "UTF-8")
    ExitApp(1)
}

HotkeyHelpRunAllTests() {
    HotkeyHelpTestContainsCodexMenuHotkey()
    HotkeyHelpTestDoesNotListDisabledLlcModule()
    HotkeyHelpTestDisplayTextHasReadableGroups()
    HotkeyHelpTestTrayInitializationCanRun()
}

HotkeyHelpAssertTrue(value, caseName) {
    global g_TestPassCount
    if !value {
        throw Error(caseName " 断言失败：结果应为 true。")
    }
    g_TestPassCount += 1
}

HotkeyHelpAssertFalse(value, caseName) {
    global g_TestPassCount
    if value {
        throw Error(caseName " 断言失败：结果应为 false。")
    }
    g_TestPassCount += 1
}

HotkeyHelpTestContainsCodexMenuHotkey() {
    text := HotkeyHelpBuildDisplayText()
    HotkeyHelpAssertTrue(InStr(text, "Ctrl+Alt+F12"), "应展示 Codex 预设热键")
    HotkeyHelpAssertTrue(InStr(text, "Codex 预设菜单"), "应说明 Codex 预设用途")
}

HotkeyHelpTestDoesNotListDisabledLlcModule() {
    text := HotkeyHelpBuildDisplayText()
    HotkeyHelpAssertFalse(InStr(text, "LLC"), "不应展示被 main.ahk 注释禁用的 LLC 模块")
    HotkeyHelpAssertFalse(InStr(text, "$F"), "不应展示禁用模块里的 F 热键")
}

HotkeyHelpTestDisplayTextHasReadableGroups() {
    text := HotkeyHelpBuildDisplayText()
    HotkeyHelpAssertTrue(InStr(text, "[文本处理]"), "应包含文本处理分组")
    HotkeyHelpAssertTrue(InStr(text, "[沙盒中转]"), "应包含沙盒中转分组")
    HotkeyHelpAssertTrue(InStr(text, "[窗口 / 系统]"), "应包含窗口系统分组")
}

HotkeyHelpTestTrayInitializationCanRun() {
    ; 这个用例模拟 main.ahk 启动阶段的托盘菜单挂载。
    ; 重点不是检查视觉效果，而是确保 A_TrayMenu.Add("Codex 预设", 子菜单对象)
    ; 这条真实启动路径不会因为参数类型、菜单对象构造等问题在 Reload 时弹错。
    root := A_Temp "\ahk_hotkey_help_tray_test_" A_TickCount
    liveDir := root "\live"
    try {
        HotkeyHelpWriteText(root "\profiles.ini", "
        (
[haibao]
display_name=海豹云-天才程序员
auth_path=secrets\haibao\auth.json
config_path=secrets\haibao\config.toml
        )")
        HotkeyHelpWriteText(root "\secrets\haibao\auth.json", "{`"OPENAI_API_KEY`":`"test-key`"}")
        HotkeyHelpWriteText(root "\secrets\haibao\config.toml", "model = `"gpt-test`"`n")
        HotkeyHelpWriteText(liveDir "\auth.json", "{`"OPENAI_API_KEY`":`"test-key`"}")
        HotkeyHelpWriteText(liveDir "\config.toml", "model = `"gpt-test`"`n")

        AhkToolkitInitializeTrayMenu(root, liveDir)
        HotkeyHelpAssertTrue(true, "托盘菜单初始化应能执行完成")
    } finally {
        if DirExist(root) {
            try DirDelete(root, true)
        }
    }
}

HotkeyHelpWriteText(path, text) {
    ; 测试辅助函数：写入文本前先确保父目录存在。
    ; 只写 A_Temp 下的临时文件，不碰真实 Codex 配置。
    SplitPath(path, , &dir)
    if !DirExist(dir) {
        DirCreate(dir)
    }
    if FileExist(path) {
        FileDelete(path)
    }
    FileAppend(text, path, "UTF-8")
}
