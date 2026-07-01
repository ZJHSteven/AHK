#Requires AutoHotkey v2.0
; ============================================
; ChatGPT Chrome 浮窗模块测试
; --------------------------------------------
; 这组测试只验证“纯逻辑”：
; - 配置解析默认值；
; - window/app 模式归一化；
; - 启动命令拼装；
; - 居中矩形与边界收敛。
;
; 不做真实 Chrome 启动自动化，避免对本机当前浏览器会话造成干扰。
; ============================================

#Include ..\modules\utils.ahk
#Include ..\modules\chatgpt_chrome_window.ahk

global g_TestPassCount := 0

try {
    ChatGptChromeRunAllTests()
    FileAppend("OK: " g_TestPassCount " tests passed.`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " err.Message "`n", "*", "UTF-8")
    ExitApp(1)
}

ChatGptChromeRunAllTests() {
    root := A_Temp "\ahk_chatgpt_chrome_window_tests_" A_TickCount
    try {
        ChatGptChromeTestModeNormalization()
        ChatGptChromeTestNonNegativeIntParsing()
        ChatGptChromeTestLaunchDebounce()
        ChatGptChromeTestExternalLinkRouterPath(root)
        ChatGptChromeTestBuildTrayMenuCanRun()
        ChatGptChromeTestExternalRouterDisabledDoesNotStart()
        ChatGptChromeTestBrowserTitleHeuristics()
        ChatGptChromeTestDesktopRecallGate()
        ChatGptChromeTestBuildWindowCommand()
        ChatGptChromeTestBuildAppCommand()
        ChatGptChromeTestCenteredRect()
        ChatGptChromeTestNormalizeRectClampsToWorkArea()
        ChatGptChromeTestIsWindowMinimizedHandlesInvalidHwnd()
        ChatGptChromeTestResolveTargetRectIgnoresSavedRectWhenModeChanged()
        ChatGptChromeTestResolveTargetRectIgnoresSavedRectWhenPolicyChanged()
        ChatGptChromeTestReadSettingsFallsBackToDefaults(root)
        ChatGptChromeTestReadSettingsRespectsConfig(root)
    } finally {
        if DirExist(root) {
            try DirDelete(root, true)
        }
    }
}

ChatGptChromeAssertTrue(value, caseName) {
    global g_TestPassCount
    if !value {
        throw Error(caseName " 断言失败：结果应为 true。")
    }
    g_TestPassCount += 1
}

ChatGptChromeAssertEqual(actual, expected, caseName) {
    global g_TestPassCount
    if (actual != expected) {
        throw Error(caseName " 断言失败。期望：" expected "，实际：" actual)
    }
    g_TestPassCount += 1
}

ChatGptChromeWriteText(path, text) {
    SplitPath(path, , &dir)
    if !DirExist(dir) {
        DirCreate(dir)
    }
    if FileExist(path) {
        FileDelete(path)
    }
    FileAppend(text, path, "UTF-8")
}

ChatGptChromeTestModeNormalization() {
    ChatGptChromeAssertEqual(ChatGptChromeNormalizeWindowMode("app"), "app", "app 模式应保留")
    ChatGptChromeAssertEqual(ChatGptChromeNormalizeWindowMode("APP"), "app", "模式大小写应被归一化")
    ChatGptChromeAssertEqual(ChatGptChromeNormalizeWindowMode("window"), "window", "window 模式应保留")
    ChatGptChromeAssertEqual(ChatGptChromeNormalizeWindowMode("weird"), "window", "非法模式应回退为 window")
}

ChatGptChromeTestNonNegativeIntParsing() {
    ChatGptChromeAssertEqual(ChatGptChromeParseNonNegativeInt("9222", 1), 9222, "端口数字应正常解析")
    ChatGptChromeAssertEqual(ChatGptChromeParseNonNegativeInt("0", 1), 0, "0 应允许用于关闭端口参数")
    ChatGptChromeAssertEqual(ChatGptChromeParseNonNegativeInt("-1", 9222), 9222, "负数应回退默认端口")
    ChatGptChromeAssertEqual(ChatGptChromeParseNonNegativeInt("abc", 9222), 9222, "非数字应回退默认端口")
}

ChatGptChromeTestLaunchDebounce() {
    ChatGptChromeAssertTrue(ChatGptChromeCanStartNewLaunch(5000, 0, false, 1200), "首次启动请求应允许")
    ChatGptChromeAssertTrue(!ChatGptChromeCanStartNewLaunch(5500, 5000, false, 1200), "防抖窗口内不应重复启动")
    ChatGptChromeAssertTrue(!ChatGptChromeCanStartNewLaunch(7000, 5000, true, 1200), "上一轮启动未完成时不应重复启动")
    ChatGptChromeAssertTrue(ChatGptChromeCanStartNewLaunch(7001, 5000, false, 1200), "超过防抖时间后应允许再次启动")
}

ChatGptChromeTestExternalLinkRouterPath(root) {
    expected := root "\tools\chatgpt_external_link_router.mjs"
    ChatGptChromeAssertEqual(ChatGptChromeExternalLinkRouterPath(root), expected, "外链路由脚本路径应位于 tools 目录")
}

ChatGptChromeTestBuildTrayMenuCanRun() {
    trayMenu := ChatGptChromeBuildTrayMenu()
    ChatGptChromeAssertTrue(IsObject(trayMenu), "ChatGPT 浮窗托盘子菜单应能构造")
}

ChatGptChromeTestExternalRouterDisabledDoesNotStart() {
    result := ChatGptChromeStartExternalLinkRouter(Map("externalLinksEnabled", false))
    ChatGptChromeAssertTrue(!result["ok"], "外链路由关闭时不应启动")
    ChatGptChromeAssertTrue(InStr(result["message"], "配置中关闭") > 0, "外链路由关闭时应给出明确提示")
}

ChatGptChromeTestBrowserTitleHeuristics() {
    ChatGptChromeAssertTrue(ChatGptChromeLooksLikeRegularBrowserTitle("测试页面 - Google Chrome"), "普通浏览器标题应识别为 regular browser")
    ChatGptChromeAssertTrue(!ChatGptChromeLooksLikeRegularBrowserTitle("Quest 3 快速游戏推荐"), "会话名标题不应被误判成普通浏览器")
    ChatGptChromeAssertTrue(!ChatGptChromeLooksLikeRegularBrowserTitle("ChatGPT"), "app 标题不应被误判成普通浏览器")
    ChatGptChromeAssertTrue(ChatGptChromeLooksLikeConversationAppTitle("Quest 3 快速游戏推荐"), "具体会话名应识别为 conversation app title")
    ChatGptChromeAssertTrue(!ChatGptChromeLooksLikeConversationAppTitle("ChatGPT"), "泛化 ChatGPT 标题不应识别为 conversation app title")
}

ChatGptChromeTestDesktopRecallGate() {
    ChatGptChromeAssertTrue(ChatGptChromeShouldAttemptDesktopRecall(true, 1), "可见且 cloak 时应进入跨桌面补救路径")
    ChatGptChromeAssertTrue(ChatGptChromeShouldAttemptDesktopRecall(true, 2), "可见且被 Shell cloak 时应进入跨桌面补救路径")
    ChatGptChromeAssertTrue(!ChatGptChromeShouldAttemptDesktopRecall(false, 2), "不可见窗口不应触发跨桌面补救")
    ChatGptChromeAssertTrue(!ChatGptChromeShouldAttemptDesktopRecall(true, 0), "未 cloak 的可见窗口不应触发跨桌面补救")
}

ChatGptChromeTestBuildWindowCommand() {
    settings := Map(
        "chromePath", "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "url", "https://chatgpt.com/",
        "userDataDir", "D:\AppData\Chrome\Chrome-CDP\User Data",
        "profileDirectory", "Default",
        "remoteDebuggingPort", 9222,
        "remoteDebuggingAddress", "127.0.0.1",
        "noFirstRun", true,
        "noDefaultBrowserCheck", true,
        "windowMode", "window"
    )
    rect := Map("x", 120, "y", 80, "w", 1180, "h", 820)
    command := ChatGptChromeBuildLaunchCommand(settings, rect)

    ChatGptChromeAssertTrue(InStr(command, "--profile-directory=" Chr(34) "Default" Chr(34)), "window 模式应指定 Default Profile")
    ChatGptChromeAssertTrue(InStr(command, "--user-data-dir=" Chr(34) "D:\AppData\Chrome\Chrome-CDP\User Data" Chr(34)), "window 模式应指定 D 盘 User Data")
    ChatGptChromeAssertTrue(InStr(command, "--remote-debugging-port=9222"), "window 模式应打开 9222 调试端口")
    ChatGptChromeAssertTrue(InStr(command, "--remote-debugging-address=" Chr(34) "127.0.0.1" Chr(34)), "window 模式应限制调试地址为本机")
    ChatGptChromeAssertTrue(InStr(command, "--no-first-run"), "window 模式应跳过首次启动提示")
    ChatGptChromeAssertTrue(InStr(command, "--no-default-browser-check"), "window 模式不应提示设为默认浏览器")
    ChatGptChromeAssertTrue(InStr(command, "--new-window"), "window 模式应包含 --new-window")
    ChatGptChromeAssertTrue(InStr(command, "--window-size=1180,820"), "window 模式应包含尺寸参数")
    ChatGptChromeAssertTrue(InStr(command, "--window-position=120,80"), "window 模式应包含位置参数")
    ChatGptChromeAssertTrue(InStr(command, Chr(34) "https://chatgpt.com/" Chr(34)), "window 模式应把 URL 作为独立参数")
}

ChatGptChromeTestBuildAppCommand() {
    settings := Map(
        "chromePath", "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "url", "https://chatgpt.com/",
        "userDataDir", "D:\AppData\Chrome\Chrome-CDP\User Data",
        "profileDirectory", "Default",
        "remoteDebuggingPort", 9222,
        "remoteDebuggingAddress", "127.0.0.1",
        "noFirstRun", true,
        "noDefaultBrowserCheck", true,
        "windowMode", "app"
    )
    rect := Map("x", 50, "y", 40, "w", 900, "h", 700)
    command := ChatGptChromeBuildLaunchCommand(settings, rect)

    ChatGptChromeAssertTrue(InStr(command, "--app=" Chr(34) "https://chatgpt.com/" Chr(34)), "app 模式应包含 --app=URL")
    ChatGptChromeAssertTrue(!InStr(command, "--new-window"), "app 模式不应再附带 --new-window")
}

ChatGptChromeTestCenteredRect() {
    rect := ChatGptChromeComputeCenteredRect(0, 0, 1920, 1040, 1180, 820)
    ChatGptChromeAssertEqual(rect["w"], 1180, "居中矩形宽度")
    ChatGptChromeAssertEqual(rect["h"], 820, "居中矩形高度")
    ChatGptChromeAssertEqual(rect["x"], 370, "居中矩形 X")
    ChatGptChromeAssertEqual(rect["y"], 110, "居中矩形 Y")
}

ChatGptChromeTestNormalizeRectClampsToWorkArea() {
    rect := ChatGptChromeNormalizeRect(Map("x", -8000, "y", -6000, "w", 5000, "h", 4000))
    workArea := ChatGptChromeGetWorkAreaForRect(rect)

    ChatGptChromeAssertTrue(rect["x"] >= workArea["left"], "归一化后 X 不应越过左边界")
    ChatGptChromeAssertTrue(rect["y"] >= workArea["top"], "归一化后 Y 不应越过上边界")
    ChatGptChromeAssertTrue(rect["x"] + rect["w"] <= workArea["right"], "归一化后右边界应留在工作区内")
    ChatGptChromeAssertTrue(rect["y"] + rect["h"] <= workArea["bottom"], "归一化后下边界应留在工作区内")
}

ChatGptChromeTestIsWindowMinimizedHandlesInvalidHwnd() {
    tempGui := Gui()
    tempGui.Show("Hide")
    hwnd := tempGui.Hwnd
    tempGui.Destroy()
    result := ChatGptChromeIsWindowMinimized(hwnd)
    ChatGptChromeAssertTrue(!result, "失效 hwnd 不应再抛错，而应安全返回 false")
}

ChatGptChromeTestReadSettingsFallsBackToDefaults(root) {
    settings := ChatGptChromeReadSettings(root)
    ChatGptChromeAssertEqual(settings["url"], "https://chatgpt.com/", "缺配置时应回退官方 URL")
    ChatGptChromeAssertEqual(settings["userDataDir"], "D:\AppData\Chrome\Chrome-CDP\User Data", "缺配置时应回退 D 盘 CDP User Data")
    ChatGptChromeAssertEqual(settings["profileDirectory"], "Default", "缺配置时应回退 Default Profile")
    ChatGptChromeAssertEqual(settings["remoteDebuggingPort"], 9222, "缺配置时应回退 9222 调试端口")
    ChatGptChromeAssertEqual(settings["remoteDebuggingAddress"], "127.0.0.1", "缺配置时应回退本机调试地址")
    ChatGptChromeAssertTrue(settings["noFirstRun"], "缺配置时应默认跳过首次启动提示")
    ChatGptChromeAssertTrue(settings["noDefaultBrowserCheck"], "缺配置时应默认不检查默认浏览器")
    ChatGptChromeAssertEqual(settings["windowMode"], "app", "缺配置时应回退 app 小窗模式")
    ChatGptChromeAssertEqual(settings["defaultWidth"], 540, "缺配置时应回退默认宽度")
    ChatGptChromeAssertEqual(settings["defaultHeight"], 760, "缺配置时应回退默认高度")
    ChatGptChromeAssertTrue(settings["alwaysOnTop"], "缺配置时应默认置顶")
    ChatGptChromeAssertTrue(settings["disableCloseButton"], "缺配置时应默认禁用关闭按钮")
}

ChatGptChromeTestReadSettingsRespectsConfig(root) {
    configPath := ChatGptChromeConfigPath(root)
    ChatGptChromeWriteText(configPath, "
(
[launch]
url=https://chatgpt.com/g/g-123-demo
chrome_path=C:\Tools\Chrome\chrome.exe
user_data_dir=D:\CustomChrome\User Data
profile_directory=Default
remote_debugging_port=9333
remote_debugging_address=127.0.0.2
no_first_run=0
no_default_browser_check=0
window_mode=app
startup_timeout_ms=12000

[window]
default_width=1024
default_height=768
always_on_top=0
disable_close_button=0

[external_links]
enabled=0
firefox_path=C:\Tools\Firefox\firefox.exe
node_path=C:\Tools\Node\node.exe
)")

    settings := ChatGptChromeReadSettings(root)
    ChatGptChromeAssertEqual(settings["url"], "https://chatgpt.com/g/g-123-demo", "应读取配置中的 URL")
    ChatGptChromeAssertEqual(settings["chromePath"], "C:\Tools\Chrome\chrome.exe", "应读取配置中的 Chrome 路径")
    ChatGptChromeAssertEqual(settings["userDataDir"], "D:\CustomChrome\User Data", "应读取配置中的 User Data 路径")
    ChatGptChromeAssertEqual(settings["remoteDebuggingPort"], 9333, "应读取配置中的 CDP 端口")
    ChatGptChromeAssertEqual(settings["remoteDebuggingAddress"], "127.0.0.2", "应读取配置中的 CDP 地址")
    ChatGptChromeAssertTrue(!settings["noFirstRun"], "应读取首次启动提示开关")
    ChatGptChromeAssertTrue(!settings["noDefaultBrowserCheck"], "应读取默认浏览器检查开关")
    ChatGptChromeAssertEqual(settings["windowMode"], "app", "应读取配置中的 app 模式")
    ChatGptChromeAssertEqual(settings["startupTimeoutMs"], 12000, "应读取配置中的超时时间")
    ChatGptChromeAssertEqual(settings["defaultWidth"], 1024, "应读取配置中的默认宽度")
    ChatGptChromeAssertEqual(settings["defaultHeight"], 768, "应读取配置中的默认高度")
    ChatGptChromeAssertTrue(!settings["alwaysOnTop"], "应读取配置中的置顶开关")
    ChatGptChromeAssertTrue(!settings["disableCloseButton"], "应读取配置中的关闭按钮开关")
    ChatGptChromeAssertTrue(!settings["externalLinksEnabled"], "应读取外链路由开关")
    ChatGptChromeAssertEqual(settings["firefoxPath"], "C:\Tools\Firefox\firefox.exe", "应读取 Firefox 路径")
    ChatGptChromeAssertEqual(settings["nodePath"], "C:\Tools\Node\node.exe", "应读取 Node 路径")
}

ChatGptChromeTestResolveTargetRectIgnoresSavedRectWhenModeChanged() {
    settings := Map(
        "defaultWidth", 540,
        "defaultHeight", 760,
        "windowMode", "app"
    )
    state := Map(
        "x", 10,
        "y", 10,
        "w", 1600,
        "h", 1000,
        "hasRect", true,
        "savedWindowMode", "window",
        "rectPolicyVersion", g_ChatGptChromeStateRectPolicyVersion
    )
    rect := ChatGptChromeResolveTargetRect(settings, state)

    ChatGptChromeAssertEqual(rect["w"], 540, "模式切换后不应继续沿用旧的大宽度")
    ChatGptChromeAssertEqual(rect["h"], 760, "模式切换后不应继续沿用旧的大高度")
}

ChatGptChromeTestResolveTargetRectIgnoresSavedRectWhenPolicyChanged() {
    settings := Map(
        "defaultWidth", 540,
        "defaultHeight", 760,
        "windowMode", "app"
    )
    state := Map(
        "x", 10,
        "y", 10,
        "w", 1600,
        "h", 1000,
        "hasRect", true,
        "savedWindowMode", "app",
        "rectPolicyVersion", g_ChatGptChromeStateRectPolicyVersion - 1
    )
    rect := ChatGptChromeResolveTargetRect(settings, state)

    ChatGptChromeAssertEqual(rect["w"], 540, "小窗策略版本变化后不应继续沿用旧大宽度")
    ChatGptChromeAssertEqual(rect["h"], 760, "小窗策略版本变化后不应继续沿用旧大高度")
}
