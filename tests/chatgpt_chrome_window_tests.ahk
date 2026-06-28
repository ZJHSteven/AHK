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
        ChatGptChromeTestBuildWindowCommand()
        ChatGptChromeTestBuildAppCommand()
        ChatGptChromeTestCenteredRect()
        ChatGptChromeTestNormalizeRectClampsToWorkArea()
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

ChatGptChromeTestBuildWindowCommand() {
    settings := Map(
        "chromePath", "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "url", "https://chatgpt.com/",
        "profileDirectory", "Default",
        "windowMode", "window"
    )
    rect := Map("x", 120, "y", 80, "w", 1180, "h", 820)
    command := ChatGptChromeBuildLaunchCommand(settings, rect)

    ChatGptChromeAssertTrue(InStr(command, "--profile-directory=" Chr(34) "Default" Chr(34)), "window 模式应指定 Default Profile")
    ChatGptChromeAssertTrue(InStr(command, "--new-window"), "window 模式应包含 --new-window")
    ChatGptChromeAssertTrue(InStr(command, "--window-size=1180,820"), "window 模式应包含尺寸参数")
    ChatGptChromeAssertTrue(InStr(command, "--window-position=120,80"), "window 模式应包含位置参数")
    ChatGptChromeAssertTrue(InStr(command, Chr(34) "https://chatgpt.com/" Chr(34)), "window 模式应把 URL 作为独立参数")
}

ChatGptChromeTestBuildAppCommand() {
    settings := Map(
        "chromePath", "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "url", "https://chatgpt.com/",
        "profileDirectory", "Default",
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

ChatGptChromeTestReadSettingsFallsBackToDefaults(root) {
    settings := ChatGptChromeReadSettings(root)
    ChatGptChromeAssertEqual(settings["url"], "https://chatgpt.com/", "缺配置时应回退官方 URL")
    ChatGptChromeAssertEqual(settings["profileDirectory"], "Default", "缺配置时应回退 Default Profile")
    ChatGptChromeAssertEqual(settings["windowMode"], "window", "缺配置时应回退普通窗口模式")
    ChatGptChromeAssertEqual(settings["defaultWidth"], 1180, "缺配置时应回退默认宽度")
    ChatGptChromeAssertEqual(settings["defaultHeight"], 820, "缺配置时应回退默认高度")
    ChatGptChromeAssertTrue(settings["alwaysOnTop"], "缺配置时应默认置顶")
}

ChatGptChromeTestReadSettingsRespectsConfig(root) {
    configPath := ChatGptChromeConfigPath(root)
    ChatGptChromeWriteText(configPath, "
    (
[launch]
url=https://chatgpt.com/g/g-123-demo
chrome_path=C:\Tools\Chrome\chrome.exe
profile_directory=Default
window_mode=app
startup_timeout_ms=12000

[window]
default_width=1024
default_height=768
always_on_top=0
    )")

    settings := ChatGptChromeReadSettings(root)
    ChatGptChromeAssertEqual(settings["url"], "https://chatgpt.com/g/g-123-demo", "应读取配置中的 URL")
    ChatGptChromeAssertEqual(settings["chromePath"], "C:\Tools\Chrome\chrome.exe", "应读取配置中的 Chrome 路径")
    ChatGptChromeAssertEqual(settings["windowMode"], "app", "应读取配置中的 app 模式")
    ChatGptChromeAssertEqual(settings["startupTimeoutMs"], 12000, "应读取配置中的超时时间")
    ChatGptChromeAssertEqual(settings["defaultWidth"], 1024, "应读取配置中的默认宽度")
    ChatGptChromeAssertEqual(settings["defaultHeight"], 768, "应读取配置中的默认高度")
    ChatGptChromeAssertTrue(!settings["alwaysOnTop"], "应读取配置中的置顶开关")
}
