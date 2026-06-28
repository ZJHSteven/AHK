; ============================================
; ChatGPT Chrome 浮窗模块
; --------------------------------------------
; 这个模块负责把“Chrome 里的 ChatGPT 页面”当成一个可被 AHK 管理的浮动窗。
;
; 核心能力：
; 1) 用 Alt+Space 统一控制“启动 / 唤起 / 收起”。
; 2) 复用 Chrome 默认 Profile，不新建独立 Profile。
; 3) 默认走普通浏览器窗口模式，保留多标签页能力。
; 4) 支持切到 app 模式，但只作为配置项保留，不默认启用。
; 5) 记住用户最后一次手动拖动/缩放后的窗口位置和大小。
; 6) 保持窗口置顶，尽量模拟“桌面小窗工作台”的使用手感。
; 7) 默认禁用右上角关闭按钮，避免误点 X 导致整个 ChatGPT 页面重开。
;
; 设计取舍：
; - 由于用户明确要求“不要新建 Profile”，这里不能靠独立 user-data-dir
;   来强隔离出一套完全独立的 Chrome 实例。
; - 因此本模块采用“记录自己启动出来的那个窗口 HWND”为主，
;   再辅以轻量启发式重新识别，尽量稳定管理同一个浮窗。
; - 如果用户手动把标签拖成新的窗口、或彻底关闭该窗口，下一次热键会重新启动。
; - 由于这是在“外部 Chrome 窗口”上做控制，而不是自己绘制一个 GUI，
;   所以最稳妥的“防误关”方案不是拦截关闭后再恢复，
;   而是直接把 Close 按钮禁用掉，并把“真正关闭”收口到 AHK 托盘菜单。
; ============================================

global g_ChatGptChromeTrackIntervalMs := 800
global g_ChatGptChromeLastSavedRectSignature := ""

; 模块初始化。
; 入参：无。
; 出参：无。
; 说明：
; 1) 这里只做一次性初始化。
; 2) 通过定时器持续记录当前受管窗口的最新位置与大小，
;    这样用户即使只是拖了一下窗口、还没按“收起”，状态也不会丢。
ChatGptChromeWindowInitialize() {
    static initialized := false
    if initialized {
        return
    }

    initialized := true
    ChatGptChromeEnsureStateDirectory()
    SetTimer(ChatGptChromeTrackManagedWindowPlacement, g_ChatGptChromeTrackIntervalMs)
}

; 切换 ChatGPT Chrome 浮窗的总入口。
; 入参：无。
; 出参：无；失败时用 Toast 提示原因。
; 逻辑顺序：
; 1) 先尽量找到“当前受管的那个 ChatGPT Chrome 窗口”。
; 2) 找到后：
;    - 若被隐藏/最小化：恢复并激活；
;    - 若当前就在前台：保存位置后隐藏；
;    - 若存在但不在前台：激活并提到最上层。
; 3) 若根本找不到：启动一个新的 Chrome 窗口并打开 ChatGPT。
ChatGptChromeToggleWindow() {
    ChatGptChromeWindowInitialize()
    settings := ChatGptChromeReadSettings()

    if (settings["chromePath"] = "") {
        Toast("未找到 Chrome，可在 config\\chatgpt_chrome_window.ini 里手动填写 chrome_path。", 2600)
        return
    }

    hwnd := ChatGptChromeResolveManagedWindow()
    if hwnd {
        if ChatGptChromeIsWindowMinimized(hwnd) || !ChatGptChromeIsWindowVisible(hwnd) {
            ChatGptChromeShowManagedWindow(hwnd, settings)
            Toast("已恢复 ChatGPT 浮窗")
            return
        }

        if WinActive("ahk_id " hwnd) {
            ChatGptChromeSaveWindowPlacement(hwnd)
            WinHide("ahk_id " hwnd)
            Toast("已收起 ChatGPT 浮窗")
            return
        }

        ChatGptChromeShowManagedWindow(hwnd, settings)
        Toast("已唤起 ChatGPT 浮窗")
        return
    }

    launchResult := ChatGptChromeLaunchManagedWindow(settings)
    if !launchResult["ok"] {
        Toast(launchResult["message"], 3200)
        return
    }

    Toast("已启动 ChatGPT 浮窗")
}

; 读取模块所在项目根目录。
; 入参：
; - root：测试时可传临时根目录；正常运行留空。
; 出参：项目根目录绝对路径。
ChatGptChromeProjectRoot(root := "") {
    if (root != "") {
        return root
    }

    SplitPath(A_LineFile, , &moduleDir)
    return RegExReplace(moduleDir, "\\modules$")
}

; 返回静态功能配置文件路径。
; 入参：可选 root。
; 出参：绝对路径。
ChatGptChromeConfigPath(root := "") {
    return ChatGptChromeProjectRoot(root) "\config\chatgpt_chrome_window.ini"
}

; 返回本地状态文件路径。
; 入参：可选 root。
; 出参：绝对路径。
; 说明：状态文件放到 logs 下，是为了避免频繁更新功能配置文件。
ChatGptChromeStatePath(root := "") {
    return ChatGptChromeProjectRoot(root) "\logs\chatgpt_chrome_window_state.ini"
}

; 确保状态目录存在。
; 入参：可选 root。
; 出参：无。
ChatGptChromeEnsureStateDirectory(root := "") {
    statePath := ChatGptChromeStatePath(root)
    SplitPath(statePath, , &stateDir)
    if !DirExist(stateDir) {
        DirCreate(stateDir)
    }
}

; 读取功能配置，并把缺省值补齐。
; 入参：可选 root。
; 出参：Map，包含 chromePath/url/profileDirectory/windowMode/defaultWidth/defaultHeight/startupTimeoutMs/alwaysOnTop。
ChatGptChromeReadSettings(root := "") {
    configPath := ChatGptChromeConfigPath(root)
    parsedIni := ChatGptChromeReadSimpleIni(configPath)
    chromePath := ChatGptChromeIniGet(parsedIni, "launch", "chrome_path", "")
    url := ChatGptChromeIniGet(parsedIni, "launch", "url", "https://chatgpt.com/")
    profileDirectory := ChatGptChromeIniGet(parsedIni, "launch", "profile_directory", "Default")
    windowMode := ChatGptChromeIniGet(parsedIni, "launch", "window_mode", "app")
    startupTimeoutMs := ChatGptChromeIniGet(parsedIni, "launch", "startup_timeout_ms", "8000")
    defaultWidth := ChatGptChromeIniGet(parsedIni, "window", "default_width", "540")
    defaultHeight := ChatGptChromeIniGet(parsedIni, "window", "default_height", "760")
    alwaysOnTop := ChatGptChromeIniGet(parsedIni, "window", "always_on_top", "1")
    disableCloseButton := ChatGptChromeIniGet(parsedIni, "window", "disable_close_button", "1")

    chromePath := Trim(chromePath, " `t`r`n")
    if (chromePath = "") {
        chromePath := ChatGptChromeDetectChromePath()
    }

    return Map(
        "chromePath", chromePath,
        "url", Trim(url, " `t`r`n"),
        "profileDirectory", Trim(profileDirectory, " `t`r`n"),
        "windowMode", ChatGptChromeNormalizeWindowMode(windowMode),
        "startupTimeoutMs", ChatGptChromeParsePositiveInt(startupTimeoutMs, 8000),
        "defaultWidth", ChatGptChromeParsePositiveInt(defaultWidth, 540),
        "defaultHeight", ChatGptChromeParsePositiveInt(defaultHeight, 760),
        "alwaysOnTop", ChatGptChromeParseIniBool(alwaysOnTop, true),
        "disableCloseButton", ChatGptChromeParseIniBool(disableCloseButton, true)
    )
}

; 读取一个足够简单、但对 UTF-8 BOM 友好的 INI。
; 入参：文件路径。
; 出参：Map(section => Map(key => value))。
; 说明：
; - 这里只服务本模块自己的配置文件，不追求通用 INI 全语法。
; - 支持：
;   1) [section]
;   2) key=value
;   3) 以 ; 或 # 开头的整行注释
; - 不解析“行尾注释”与更复杂的转义规则，因为当前配置场景不需要。
ChatGptChromeReadSimpleIni(path) {
    parsed := Map()
    if !FileExist(path) {
        return parsed
    }

    text := FileRead(path, "UTF-8")
    if (SubStr(text, 1, 1) = Chr(0xFEFF)) {
        text := SubStr(text, 2)
    }

    text := StrReplace(text, "`r", "")
    currentSection := ""
    for _, rawLine in StrSplit(text, "`n") {
        line := Trim(rawLine, " `t")
        if (line = "") {
            continue
        }
        if (SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#") {
            continue
        }
        if RegExMatch(line, "^\[(.+)\]$", &sectionMatch) {
            currentSection := Trim(sectionMatch[1], " `t")
            if !parsed.Has(currentSection) {
                parsed[currentSection] := Map()
            }
            continue
        }
        if (currentSection = "") {
            continue
        }
        if RegExMatch(line, "^(.*?)=(.*)$", &kv) {
            key := Trim(kv[1], " `t")
            value := Trim(kv[2], " `t")
            parsed[currentSection][key] := value
        }
    }
    return parsed
}

; 从已解析的简单 INI 结构里取值。
; 入参：parsedIni、section、key、defaultValue。
; 出参：命中则返回配置值，否则返回默认值。
ChatGptChromeIniGet(parsedIni, section, key, defaultValue := "") {
    if !parsedIni.Has(section) {
        return defaultValue
    }
    if !parsedIni[section].Has(key) {
        return defaultValue
    }
    return parsedIni[section][key]
}

; 把任意文本归一成允许的窗口模式。
; 入参：用户配置里的 mode 文本。
; 出参：window 或 app；非法值统一回退到 window。
ChatGptChromeNormalizeWindowMode(modeText) {
    normalized := StrLower(Trim(modeText, " `t`r`n"))
    return (normalized = "app") ? "app" : "window"
}

; 解析 INI 风格布尔值。
; 入参：文本 + 默认值。
; 出参：true / false。
ChatGptChromeParseIniBool(valueText, defaultValue := false) {
    normalized := StrLower(Trim(valueText, " `t`r`n"))
    if (normalized = "") {
        return defaultValue
    }
    if (normalized = "1" || normalized = "true" || normalized = "yes" || normalized = "on") {
        return true
    }
    if (normalized = "0" || normalized = "false" || normalized = "no" || normalized = "off") {
        return false
    }
    return defaultValue
}

; 把文本解析成正整数。
; 入参：原始文本 + 默认值。
; 出参：正整数；非法值回退默认值。
ChatGptChromeParsePositiveInt(valueText, defaultValue) {
    trimmed := Trim(valueText, " `t`r`n")
    if (trimmed = "" || !RegExMatch(trimmed, "^-?\d+$")) {
        return defaultValue
    }

    value := Integer(trimmed)
    return (value > 0) ? value : defaultValue
}

; 自动探测 Chrome 安装路径。
; 入参：无。
; 出参：chrome.exe 绝对路径；找不到时返回空字符串。
ChatGptChromeDetectChromePath() {
    candidates := [
        A_ProgramFiles "\Google\Chrome\Application\chrome.exe",
        A_ProgramFiles " (x86)\Google\Chrome\Application\chrome.exe",
        EnvGet("LOCALAPPDATA") "\Google\Chrome\Application\chrome.exe"
    ]

    for _, candidate in candidates {
        if FileExist(candidate) {
            return candidate
        }
    }
    return ""
}

; 读取本地状态。
; 入参：可选 root。
; 出参：Map，包含 lastHwnd/x/y/w/h/hasRect/savedWindowMode。
ChatGptChromeReadState(root := "") {
    statePath := ChatGptChromeStatePath(root)
    lastHwnd := FileExist(statePath) ? IniRead(statePath, "window", "last_hwnd", "") : ""
    x := FileExist(statePath) ? IniRead(statePath, "window", "x", "") : ""
    y := FileExist(statePath) ? IniRead(statePath, "window", "y", "") : ""
    w := FileExist(statePath) ? IniRead(statePath, "window", "w", "") : ""
    h := FileExist(statePath) ? IniRead(statePath, "window", "h", "") : ""
    savedWindowMode := FileExist(statePath) ? IniRead(statePath, "window", "window_mode", "") : ""

    hasRect := RegExMatch(x, "^-?\d+$")
        && RegExMatch(y, "^-?\d+$")
        && RegExMatch(w, "^-?\d+$")
        && RegExMatch(h, "^-?\d+$")

    return Map(
        "lastHwnd", RegExMatch(lastHwnd, "^\d+$") ? Integer(lastHwnd) : 0,
        "x", hasRect ? Integer(x) : 0,
        "y", hasRect ? Integer(y) : 0,
        "w", hasRect ? Integer(w) : 0,
        "h", hasRect ? Integer(h) : 0,
        "hasRect", hasRect,
        "savedWindowMode", Trim(savedWindowMode, " `t`r`n")
    )
}

; 把状态写回本地 ini。
; 入参：state Map；可选 root。
; 出参：无。
ChatGptChromeWriteState(state, root := "") {
    ChatGptChromeEnsureStateDirectory(root)
    statePath := ChatGptChromeStatePath(root)
    IniWrite(state["lastHwnd"], statePath, "window", "last_hwnd")
    IniWrite(state["x"], statePath, "window", "x")
    IniWrite(state["y"], statePath, "window", "y")
    IniWrite(state["w"], statePath, "window", "w")
    IniWrite(state["h"], statePath, "window", "h")
    IniWrite(state.Has("savedWindowMode") ? state["savedWindowMode"] : "", statePath, "window", "window_mode")
}

; 清空“当前受管窗口”的句柄记忆，但保留位置/大小。
; 入参：可选 root。
; 出参：无。
; 说明：
; - 当窗口已经被用户或系统真正关闭后，保留旧 hwnd 只会造成后续恢复时报错。
; - 这里故意不删除 x/y/w/h，因为用户通常仍希望下次新开时回到原位置。
ChatGptChromeForgetManagedWindow(root := "") {
    state := ChatGptChromeReadState(root)
    state["lastHwnd"] := 0
    ChatGptChromeWriteState(state, root)
}

; 尝试解析当前正在被本模块管理的窗口。
; 入参：无。
; 出参：窗口 HWND；找不到时返回 0。
; 说明：
; 1) 优先信任状态文件里保存的 last_hwnd。
; 2) 如果脚本重载或浏览器窗口重建导致 HWND 失效，则尝试从现有 Chrome 窗口里重新识别。
ChatGptChromeResolveManagedWindow() {
    state := ChatGptChromeReadState()
    if ChatGptChromeIsWindowHandleUsable(state["lastHwnd"]) {
        return state["lastHwnd"]
    }

    if (state["lastHwnd"] != 0) {
        ChatGptChromeForgetManagedWindow()
    }

    hwnd := ChatGptChromeFindManagedWindowByHeuristic(state)
    if hwnd {
        state["lastHwnd"] := hwnd
        ChatGptChromeWriteState(state)
        return hwnd
    }
    return 0
}

; 基于“标题里含 ChatGPT + 与历史矩形尽量接近”做轻量重识别。
; 入参：state Map。
; 出参：候选 HWND；找不到返回 0。
; 说明：
; - 这是启发式，不是强保证。
; - 主要用于脚本 Reload 后尽量接管已有窗口，而不是替代主识别机制。
ChatGptChromeFindManagedWindowByHeuristic(state) {
    candidateCount := 0
    bestHwnd := 0
    bestScore := -2147483648

    for _, hwnd in WinGetList("ahk_exe chrome.exe") {
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if !InStr(StrLower(title), "chatgpt") {
            continue
        }

        candidateCount += 1
        score := 0

        if state["hasRect"] {
            try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            catch {
                continue
            }
            score := -Abs(x - state["x"]) - Abs(y - state["y"]) - Abs(w - state["w"]) - Abs(h - state["h"])
        }

        if (score > bestScore) {
            bestScore := score
            bestHwnd := hwnd
        }
    }

    if (candidateCount = 1) {
        return bestHwnd
    }
    if (candidateCount > 1 && state["hasRect"] && bestHwnd) {
        return bestHwnd
    }
    return 0
}

; 判断 HWND 当前是否还是一个可用窗口。
; 入参：hwnd。
; 出参：true / false。
ChatGptChromeIsWindowHandleUsable(hwnd) {
    if !(hwnd is Integer) || (hwnd <= 0) {
        return false
    }
    return DllCall("IsWindow", "ptr", hwnd, "int") != 0
}

; 判断窗口是否可见。
; 入参：hwnd。
; 出参：true / false。
ChatGptChromeIsWindowVisible(hwnd) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }
    return DllCall("IsWindowVisible", "ptr", hwnd, "int") != 0
}

; 判断窗口是否最小化。
; 入参：hwnd。
; 出参：true / false。
ChatGptChromeIsWindowMinimized(hwnd) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }
    try {
        return WinGetMinMax("ahk_id " hwnd) = -1
    } catch TargetError {
        ChatGptChromeForgetManagedWindow()
        return false
    }
}

; 把当前窗口提升为前台并应用置顶/位置。
; 入参：hwnd、settings。
; 出参：无。
ChatGptChromeShowManagedWindow(hwnd, settings) {
    rect := ChatGptChromeResolveTargetRect(settings, ChatGptChromeReadState())
    WinShow("ahk_id " hwnd)
    if ChatGptChromeIsWindowMinimized(hwnd) {
        WinRestore("ahk_id " hwnd)
    }
    WinMove(rect["x"], rect["y"], rect["w"], rect["h"], "ahk_id " hwnd)
    ChatGptChromeApplyWindowProtections(hwnd, settings)
    WinActivate("ahk_id " hwnd)
    ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
}

; 启动一个新的受管 Chrome 窗口。
; 入参：settings。
; 出参：Map("ok", bool, "message", 文本, "hwnd", 数字)。
ChatGptChromeLaunchManagedWindow(settings) {
    beforeSet := ChatGptChromeBuildHwndSet(WinGetList("ahk_exe chrome.exe"))
    rect := ChatGptChromeResolveTargetRect(settings, ChatGptChromeReadState())
    command := ChatGptChromeBuildLaunchCommand(settings, rect)

    try Run(command)
    catch as err {
        return Map("ok", false, "message", "启动 Chrome 失败：" err.Message, "hwnd", 0)
    }

    hwnd := ChatGptChromeWaitForNewChromeWindow(beforeSet, settings["startupTimeoutMs"])
    if !hwnd {
        return Map("ok", false, "message", "Chrome 已启动，但在超时时间内没有等到新的 ChatGPT 窗口。", "hwnd", 0)
    }

    ChatGptChromeApplyWindowProtections(hwnd, settings)
    WinActivate("ahk_id " hwnd)
    ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
    return Map("ok", true, "message", "已启动 ChatGPT 浮窗", "hwnd", hwnd)
}

; 把 Chrome 启动参数拼成最终命令行。
; 入参：settings、rect。
; 出参：完整命令行字符串。
ChatGptChromeBuildLaunchCommand(settings, rect) {
    command := ChatGptChromeQuoteStandaloneArg(settings["chromePath"])
        . " --profile-directory=" ChatGptChromeQuoteSwitchValue(settings["profileDirectory"])
        . " --window-size=" rect["w"] "," rect["h"]
        . " --window-position=" rect["x"] "," rect["y"]

    if (settings["windowMode"] = "app") {
        command .= " --app=" ChatGptChromeQuoteSwitchValue(settings["url"])
    } else {
        command .= " --new-window " ChatGptChromeQuoteStandaloneArg(settings["url"])
    }
    return command
}

; 给“独立命令行参数”加引号。
; 入参：原始字符串。
; 出参：安全的命令行参数。
ChatGptChromeQuoteStandaloneArg(value) {
    return Chr(34) StrReplace(value, Chr(34), Chr(92) Chr(34)) Chr(34)
}

; 给“--key=value”里的 value 部分加引号。
; 入参：value。
; 出参：例如 "Default" 或 "https://chatgpt.com/"。
ChatGptChromeQuoteSwitchValue(value) {
    return Chr(34) StrReplace(value, Chr(34), Chr(92) Chr(34)) Chr(34)
}

; 把 HWND 数组转成便于查重的 Map。
; 入参：WinGetList 返回的数组。
; 出参：Map(hwnd => true)。
ChatGptChromeBuildHwndSet(hwndList) {
    seen := Map()
    for _, hwnd in hwndList {
        seen[hwnd] := true
    }
    return seen
}

; 等待一个“启动后新出现的 Chrome 顶层窗口”。
; 入参：启动前的 HWND 集合、超时时间（毫秒）。
; 出参：新窗口 HWND；等不到则返回 0。
ChatGptChromeWaitForNewChromeWindow(beforeSet, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount <= deadline) {
        for _, hwnd in WinGetList("ahk_exe chrome.exe") {
            if beforeSet.Has(hwnd) {
                continue
            }
            if !ChatGptChromeIsWindowHandleUsable(hwnd) {
                continue
            }
            try title := WinGetTitle("ahk_id " hwnd)
            catch {
                continue
            }

            ; 标题可能在导航早期暂时为空，所以只要窗口已经具备尺寸即可接受。
            try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            catch {
                continue
            }
            if (w > 0 && h > 0) {
                return hwnd
            }
        }
        Sleep(100)
    }
    return 0
}

; 计算本次应该应用到窗口上的矩形。
; 入参：settings、state。
; 出参：Map(x, y, w, h)。
; 逻辑：
; 1) 若已有历史矩形，优先复用；
; 2) 若没有，则根据鼠标所在显示器工作区做一个居中的默认矩形；
; 3) 最后再统一做边界收敛，避免窗口完全飞出屏幕。
ChatGptChromeResolveTargetRect(settings, state) {
    if (state["hasRect"] && state["savedWindowMode"] = settings["windowMode"]) {
        return ChatGptChromeNormalizeRect(Map(
            "x", state["x"],
            "y", state["y"],
            "w", state["w"],
            "h", state["h"]
        ))
    }

    workArea := ChatGptChromeGetMouseMonitorWorkArea()
    return ChatGptChromeComputeCenteredRect(
        workArea["left"],
        workArea["top"],
        workArea["right"],
        workArea["bottom"],
        settings["defaultWidth"],
        settings["defaultHeight"]
    )
}

; 记录当前窗口的最新位置与大小。
; 入参：hwnd；可选 root。
; 出参：true=已保存或无变化；false=读取失败。
ChatGptChromeSaveWindowPlacement(hwnd, root := "", settings := "") {
    global g_ChatGptChromeLastSavedRectSignature
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }

    try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch {
        return false
    }

    if (w <= 0 || h <= 0) {
        return false
    }

    state := Map(
        "lastHwnd", hwnd,
        "x", x,
        "y", y,
        "w", w,
        "h", h,
        "savedWindowMode", IsObject(settings) ? settings["windowMode"] : ChatGptChromeReadState(root)["savedWindowMode"]
    )
    signature := x "|" y "|" w "|" h "|" hwnd
    if (signature = g_ChatGptChromeLastSavedRectSignature) {
        return true
    }

    ChatGptChromeWriteState(state, root)
    g_ChatGptChromeLastSavedRectSignature := signature
    return true
}

; 定时追踪当前受管窗口的位置。
; 入参：无。
; 出参：无。
; 说明：
; - 这里只做“轻量快照”。
; - 只有当窗口存在、可见、且不是最小化时才会写状态。
ChatGptChromeTrackManagedWindowPlacement() {
    settings := ChatGptChromeReadSettings()
    state := ChatGptChromeReadState()
    hwnd := state["lastHwnd"]
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        if (hwnd != 0) {
            ChatGptChromeForgetManagedWindow()
        }
        return
    }
    if !ChatGptChromeIsWindowVisible(hwnd) {
        return
    }
    if ChatGptChromeIsWindowMinimized(hwnd) {
        return
    }
    ChatGptChromeApplyWindowProtections(hwnd, settings)
    ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
}

; 获取鼠标当前所在显示器的工作区。
; 入参：无。
; 出参：Map(left, top, right, bottom)。
; 说明：工作区会排除任务栏，比直接拿整块屏幕更适合放窗口。
ChatGptChromeGetMouseMonitorWorkArea() {
    MouseGetPos(&mouseX, &mouseY)
    return ChatGptChromeGetWorkAreaForPoint(mouseX, mouseY)
}

; 根据一个点，找到它所在显示器的工作区。
; 入参：x、y。
; 出参：Map(left, top, right, bottom)。
; 说明：如果该点不在任何已知工作区内，则回退主显示器。
ChatGptChromeGetWorkAreaForPoint(x, y) {
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        if (x >= left && x < right && y >= top && y < bottom) {
            return Map("left", left, "top", top, "right", right, "bottom", bottom)
        }
    }

    primary := MonitorGetPrimary()
    MonitorGetWorkArea(primary, &left, &top, &right, &bottom)
    return Map("left", left, "top", top, "right", right, "bottom", bottom)
}

; 根据一个矩形中心点，找到最适合的工作区。
; 入参：rect。
; 出参：Map(left, top, right, bottom)。
ChatGptChromeGetWorkAreaForRect(rect) {
    centerX := rect["x"] + (rect["w"] // 2)
    centerY := rect["y"] + (rect["h"] // 2)
    return ChatGptChromeGetWorkAreaForPoint(centerX, centerY)
}

; 在指定工作区内计算“居中的默认矩形”。
; 入参：工作区边界 + 期望宽高。
; 出参：Map(x, y, w, h)。
ChatGptChromeComputeCenteredRect(left, top, right, bottom, desiredWidth, desiredHeight) {
    areaWidth := right - left
    areaHeight := bottom - top
    width := Min(desiredWidth, areaWidth)
    height := Min(desiredHeight, areaHeight)
    x := left + ((areaWidth - width) // 2)
    y := top + ((areaHeight - height) // 2)
    return Map("x", x, "y", y, "w", width, "h", height)
}

; 把任意矩形收敛到所在工作区内，避免离屏。
; 入参：rect Map。
; 出参：修正后的 rect Map。
; 说明：
; - 宽高至少保留 320x240，防止状态文件意外写入过小值。
; - 若历史矩形中心点已经不在任何当前显示器工作区里，会自动回退鼠标所在屏。
ChatGptChromeNormalizeRect(rect) {
    workArea := ChatGptChromeGetWorkAreaForRect(rect)
    areaWidth := workArea["right"] - workArea["left"]
    areaHeight := workArea["bottom"] - workArea["top"]

    width := Max(320, rect["w"])
    height := Max(240, rect["h"])
    width := Min(width, areaWidth)
    height := Min(height, areaHeight)

    minX := workArea["left"]
    maxX := workArea["right"] - width
    minY := workArea["top"]
    maxY := workArea["bottom"] - height

    x := rect["x"]
    y := rect["y"]
    if (x < minX) {
        x := minX
    }
    if (x > maxX) {
        x := maxX
    }
    if (y < minY) {
        y := minY
    }
    if (y > maxY) {
        y := maxY
    }

    return Map("x", x, "y", y, "w", width, "h", height)
}

; 对受管窗口应用“置顶 + 防误关”保护。
; 入参：hwnd、settings。
; 出参：无。
; 说明：
; - 右上角关闭按钮被禁用后，用户误点 X 时不会把整个 ChatGPT 会话关掉。
; - 真正想关闭时，使用 AHK 托盘菜单“彻底关闭 ChatGPT 浮窗”。
ChatGptChromeApplyWindowProtections(hwnd, settings) {
    if settings["alwaysOnTop"] {
        WinSetAlwaysOnTop(1, "ahk_id " hwnd)
    }
    if settings["disableCloseButton"] {
        ChatGptChromeSetCloseButtonEnabled(hwnd, false)
    } else {
        ChatGptChromeSetCloseButtonEnabled(hwnd, true)
    }
}

; 启用或禁用窗口右上角关闭按钮。
; 入参：hwnd、enabled。
; 出参：true=调用成功；false=窗口无效或系统菜单不可用。
; 实现依据：
; - Windows 关闭按钮本质上挂在系统菜单的 `SC_CLOSE` 项上；
; - 禁用该菜单项后，标题栏 X 与 Alt+F4 都会一起失效或变灰。
ChatGptChromeSetCloseButtonEnabled(hwnd, enabled) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }

    hMenu := DllCall("GetSystemMenu", "ptr", hwnd, "int", false, "ptr")
    if !hMenu {
        return false
    }

    command := 0xF060  ; SC_CLOSE
    flags := enabled ? 0x0 : 0x3  ; MF_ENABLED : MF_DISABLED|MF_GRAYED
    result := DllCall("EnableMenuItem", "ptr", hMenu, "uint", command, "uint", 0x0 | flags, "int")
    DllCall("DrawMenuBar", "ptr", hwnd)
    return result != -1
}

; 从托盘菜单彻底关闭受管的 ChatGPT 浮窗。
; 入参：菜单事件参数自动传入，但本函数不使用。
; 出参：无。
; 说明：
; - 这是真正的“关闭”，不是 Alt+Space 的临时收起。
; - 关闭后会清除 last_hwnd；下次 Alt+Space 会重新新开一个 app 窗口。
ChatGptChromeForceCloseFromTray(*) {
    settings := ChatGptChromeReadSettings()
    hwnd := ChatGptChromeResolveManagedWindow()
    if !hwnd {
        Toast("当前没有可关闭的 ChatGPT 浮窗。")
        return
    }

    ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
    ChatGptChromeSetCloseButtonEnabled(hwnd, true)
    try WinClose("ahk_id " hwnd)
    Sleep(250)
    if ChatGptChromeIsWindowHandleUsable(hwnd) {
        try PostMessage(0x0112, 0xF060, 0, , "ahk_id " hwnd)
    }
    ChatGptChromeForgetManagedWindow()
    Toast("已彻底关闭 ChatGPT 浮窗")
}

; 模块载入时就启动位置跟踪器。
; 这样 main.ahk 无需额外记住“还要初始化一次 ChatGPT 浮窗模块”。
ChatGptChromeWindowInitialize()
