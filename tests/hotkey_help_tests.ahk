#Requires AutoHotkey v2.0
; ============================================
; 热键帮助模块测试
; --------------------------------------------
; 这个测试只检查显式注册表的内容，不打开真实 Gui。
; ============================================

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

