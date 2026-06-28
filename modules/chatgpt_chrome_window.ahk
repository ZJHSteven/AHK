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
global g_ChatGptChromeStateRectPolicyVersion := 2
global g_ChatGptChromeLaunchInProgress := false
global g_ChatGptChromeLaunchDebounceMs := 250
global g_ChatGptChromeLastLaunchTick := 0

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
    global g_ChatGptChromeLaunchInProgress
    global g_ChatGptChromeLastLaunchTick
    global g_ChatGptChromeLaunchDebounceMs
    ChatGptChromeWindowInitialize()
    settings := ChatGptChromeReadSettings()

    if (settings["chromePath"] = "") {
        Toast("未找到 Chrome，可在 config\\chatgpt_chrome_window.ini 里手动填写 chrome_path。", 2600)
        return
    }

    hwnd := ChatGptChromeResolveManagedWindow()
    if hwnd {
        result := ChatGptChromeHandleExistingWindow(hwnd, settings)
        if (result = "handled") {
            return
        }

        ; 只有当旧 hwnd 真失效时，才允许忘掉它并重新识别。
        ; 这次回归修复的重点，就是不能因为“跨桌面搬运失败”
        ; 就把仍然活着的旧实例当成不存在，然后误开第二个窗口。
        ChatGptChromeForgetManagedWindow()
        hwnd := ChatGptChromeResolveManagedWindow()
        if hwnd {
            result := ChatGptChromeHandleExistingWindow(hwnd, settings)
            if (result = "handled") {
                return
            }
            ChatGptChromeForgetManagedWindow()
        }
    }

    ; 在真正新开之前再做最后一轮“现存实例”检查。
    ; 只要还能找到任何一个已受管/像受管的候选，就绝不允许再次 Run 新窗。
    hwnd := ChatGptChromeResolveManagedWindow()
    if hwnd {
        result := ChatGptChromeHandleExistingWindow(hwnd, settings)
        if (result = "handled") {
            return
        }
        ChatGptChromeForgetManagedWindow()
    }

    if !ChatGptChromeCanStartNewLaunch(A_TickCount, g_ChatGptChromeLastLaunchTick, g_ChatGptChromeLaunchInProgress, g_ChatGptChromeLaunchDebounceMs) {
        return
    }

    g_ChatGptChromeLaunchInProgress := true
    g_ChatGptChromeLastLaunchTick := A_TickCount
    launchResult := ChatGptChromeLaunchManagedWindow(settings)
    g_ChatGptChromeLaunchInProgress := false
    if !launchResult["ok"] {
        Toast(launchResult["message"], 3200)
        return
    }

    Toast("已启动 ChatGPT 浮窗")
}

; 处理“已经存在的受管窗口”。
; 入参：hwnd、settings。
; 出参：
; - "handled"：本次热键已经完成处理，不应继续走新开分支。
; - "stale"：这个 hwnd 确实已经失效，可以清掉状态后继续重识别。
; 说明：
; 1) 这里把“已有实例”的所有处理都收口到一起，避免主流程里重复写三遍。
; 2) 这也是本轮回归修复的核心：只要旧实例还活着，就宁可提示“接管失败”，
;    也绝不允许继续误判成“没窗口”然后新开第二个实例。
ChatGptChromeHandleExistingWindow(hwnd, settings) {
    state := ChatGptChromeReadState()
    ChatGptChromePruneDuplicateManagedWindows(hwnd, settings, state)

    ; 正常同桌面切换时，完全不走任何额外跨桌面桥接逻辑。
    ; 只有窗口被 Shell cloak、很像“留在别的虚拟桌面上”时，
    ; 才进入较慢的跨桌面补救路径。
    if ChatGptChromeWindowNeedsDesktopRecall(hwnd) {
        if ChatGptChromeRecallWindowToCurrentDesktop(hwnd, settings) {
            Toast("已恢复 ChatGPT 浮窗")
            return "handled"
        }
        if ChatGptChromeIsWindowHandleUsable(hwnd) {
            Toast("已找到原 ChatGPT 浮窗，但本次跨桌面接管失败；未再新开实例。", 2800)
            return "handled"
        }
        return "stale"
    }

    if ChatGptChromeIsWindowVisible(hwnd) && !ChatGptChromeIsWindowMinimized(hwnd) {
        ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
        try WinHide("ahk_id " hwnd)
        catch {
            return ChatGptChromeIsWindowHandleUsable(hwnd) ? "handled" : "stale"
        }
        Toast("已收起 ChatGPT 浮窗")
        return "handled"
    }

    if ChatGptChromeShowManagedWindow(hwnd, settings) {
        Toast("已恢复 ChatGPT 浮窗")
        return "handled"
    }

    if ChatGptChromeIsWindowHandleUsable(hwnd) {
        Toast("已找到原 ChatGPT 浮窗，但恢复失败；未再新开实例。", 2600)
        return "handled"
    }
    return "stale"
}

; 托盘菜单回调包装器。
; 入参：菜单事件参数由 AHK 自动传入，但这里不使用。
; 出参：无。
; 说明：
; - `Menu.Add()` 的回调签名与普通无参函数不同；
; - 因此这里额外包一层 `(*)` 兼容托盘菜单调用约定。
ChatGptChromeToggleWindowFromTray(*) {
    ChatGptChromeToggleWindow()
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

; 判断本次是否允许再次启动新窗口。
; 入参：
; - currentTick：当前时钟。
; - lastLaunchTick：上一次发起启动请求的时钟。
; - launchInProgress：当前是否还在等待上一轮窗口出现。
; - debounceMs：防抖时间窗。
; 出参：true=允许；false=应忽略本次重复启动。
ChatGptChromeCanStartNewLaunch(currentTick, lastLaunchTick, launchInProgress, debounceMs) {
    if launchInProgress {
        return false
    }
    return (currentTick - lastLaunchTick) >= debounceMs
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
; 出参：Map，包含 lastHwnd/x/y/w/h/hasRect/savedWindowMode/rectPolicyVersion。
ChatGptChromeReadState(root := "") {
    statePath := ChatGptChromeStatePath(root)
    lastHwnd := FileExist(statePath) ? IniRead(statePath, "window", "last_hwnd", "") : ""
    x := FileExist(statePath) ? IniRead(statePath, "window", "x", "") : ""
    y := FileExist(statePath) ? IniRead(statePath, "window", "y", "") : ""
    w := FileExist(statePath) ? IniRead(statePath, "window", "w", "") : ""
    h := FileExist(statePath) ? IniRead(statePath, "window", "h", "") : ""
    savedWindowMode := FileExist(statePath) ? IniRead(statePath, "window", "window_mode", "") : ""
    rectPolicyVersion := FileExist(statePath) ? IniRead(statePath, "window", "rect_policy_version", "") : ""

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
        "savedWindowMode", Trim(savedWindowMode, " `t`r`n"),
        "rectPolicyVersion", RegExMatch(rectPolicyVersion, "^\d+$") ? Integer(rectPolicyVersion) : 0
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
    IniWrite(state.Has("rectPolicyVersion") ? state["rectPolicyVersion"] : g_ChatGptChromeStateRectPolicyVersion, statePath, "window", "rect_policy_version")
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

; 返回当前所有“像是本模块在管理的 ChatGPT 浮窗”的候选窗口。
; 入参：state Map。
; 出参：HWND 数组。
; 说明：
; - 这是单实例守卫的基础：只要这里返回非空，就说明“已经有实例存在”，
;   后续不应该再次 `Run --app=...`。
ChatGptChromeGetManagedWindowCandidates(state) {
    candidates := []
    for _, hwnd in WinGetList("ahk_exe chrome.exe") {
        if ChatGptChromeLooksLikeManagedWindow(hwnd, state) {
            candidates.Push(hwnd)
        }
    }
    return candidates
}

; 基于“Chrome 顶层窗口 + 置顶样式 + 标题形态 + 历史矩形接近度”做轻量重识别。
; 入参：state Map。
; 出参：候选 HWND；找不到返回 0。
; 说明：
; - 这是启发式，不是强保证。
; - 主要用于脚本 Reload 后尽量接管已有窗口，而不是替代主识别机制。
; - 2026-06-28 追加修正：
;   不能只认标题含 `ChatGPT`，因为 app 窗口标题会变成当前会话名，
;   例如用户截图中的 `Quest 3 快速游戏推荐`。
ChatGptChromeFindManagedWindowByHeuristic(state) {
    candidates := ChatGptChromeGetManagedWindowCandidates(state)
    bestHwnd := 0
    bestScore := -2147483648

    for _, hwnd in candidates {
        score := ChatGptChromeScoreManagedWindowCandidate(hwnd, state)

        if (score > bestScore) {
            bestScore := score
            bestHwnd := hwnd
        }
    }

    if (candidates.Length = 1) {
        return bestHwnd
    }
    if (candidates.Length > 1 && bestHwnd) {
        return bestHwnd
    }
    return 0
}

; 收敛误开的重复实例，只保留首选窗口。
; 入参：preferredHwnd、settings、state。
; 出参：无。
; 说明：
; - 这是“永远只允许一个实例存在”的执行层保护。
; - 一旦已经出现多个候选窗口，就不再让它们同时留在桌面上失控存在。
; - 优先保留 `preferredHwnd`，其余候选先尝试优雅关闭；若失败，再隐藏作为兜底。
ChatGptChromePruneDuplicateManagedWindows(preferredHwnd, settings, state) {
    candidates := ChatGptChromeGetManagedWindowCandidates(state)
    if (candidates.Length <= 1) {
        return
    }

    for _, hwnd in candidates {
        if (hwnd = preferredHwnd) {
            continue
        }
        if !ChatGptChromeIsWindowHandleUsable(hwnd) {
            continue
        }
        try ChatGptChromeSetCloseButtonEnabled(hwnd, true)
        try WinClose("ahk_id " hwnd)
        Sleep(120)
        if ChatGptChromeIsWindowHandleUsable(hwnd) {
            try PostMessage(0x0112, 0xF060, 0, , "ahk_id " hwnd)
            Sleep(120)
        }
        if ChatGptChromeIsWindowHandleUsable(hwnd) {
            try WinHide("ahk_id " hwnd)
        }
    }

    ; 这里不主动写回尺寸。
    ; 原因：
    ; - 若现场已经误开出第二个实例，首选窗口判定还处在“纠错”阶段；
    ; - 此时立刻保存 preferredHwnd 的当前尺寸，容易把误开实例的大窗尺寸污染进状态文件。
    ; 真正的尺寸保存，统一留给“显式收起 / 显式恢复 / 定时追踪”路径负责。
}

; 判断一个 Chrome 顶层窗口是否“像是”本模块管理的 ChatGPT 窗口。
; 入参：hwnd、state。
; 出参：true / false。
; 策略：
; 1) 标题直接含 `ChatGPT` 的窗口优先认为是候选。
; 2) 当前使用 app 模式时，标题往往会直接变成会话名，不再含 ` - Google Chrome`。
; 3) 我们自己的窗口会被设成 topmost，因此“Chrome + topmost”是很强的候选信号。
ChatGptChromeLooksLikeManagedWindow(hwnd, state) {
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    catch {
        return false
    }

    if (title = "") {
        return false
    }
    if InStr(StrLower(title), "chatgpt") {
        return true
    }
    if ChatGptChromeIsTopmostWindow(hwnd) {
        return true
    }
    if (state["savedWindowMode"] = "app" && !ChatGptChromeLooksLikeRegularBrowserTitle(title)) {
        return true
    }
    return false
}

; 判断标题是否更像“普通浏览器标签页窗口”。
; 入参：标题文本。
; 出参：true / false。
; 说明：
; - 普通 Chrome 窗口标题通常包含 ` - Google Chrome` 后缀。
; - app/PWA 窗口、以及 ChatGPT 会话名窗口往往没有这个后缀。
ChatGptChromeLooksLikeRegularBrowserTitle(title) {
    return InStr(title, " - Google Chrome") > 0
}

; 判断标题是否更像“具体会话名 app 窗口”，而不是泛化的 ChatGPT 首页。
; 入参：标题文本。
; 出参：true / false。
; 说明：
; - `ChatGPT` 本身是泛化首页标题。
; - 像 `Quest 3 快速游戏推荐` 这种更像用户真正工作的会话窗。
ChatGptChromeLooksLikeConversationAppTitle(title) {
    trimmed := Trim(title, " `t`r`n")
    if (trimmed = "" || StrLower(trimmed) = "chatgpt") {
        return false
    }
    return !ChatGptChromeLooksLikeRegularBrowserTitle(trimmed)
}

; 为候选窗口打分，分数越高越优先被接管。
; 入参：hwnd、state。
; 出参：整数分数。
ChatGptChromeScoreManagedWindowCandidate(hwnd, state) {
    score := 0
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)
    if InStr(StrLower(title), "chatgpt") {
        score += 1000000
    }
    if ChatGptChromeIsTopmostWindow(hwnd) {
        score += 600000
    }
    if ChatGptChromeLooksLikeConversationAppTitle(title) {
        score += 1200000
    }
    if (state["savedWindowMode"] = "app" && !ChatGptChromeLooksLikeRegularBrowserTitle(title)) {
        score += 300000
    }

    if state["hasRect"] {
        try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        catch {
            return score - 99999999
        }
        score += -Abs(x - state["x"]) - Abs(y - state["y"]) - Abs(w - state["w"]) - Abs(h - state["h"])
    }
    return score
}

; 判断窗口是否带有 topmost 扩展样式。
; 入参：hwnd。
; 出参：true / false。
ChatGptChromeIsTopmostWindow(hwnd) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }
    try exStyle := WinGetExStyle("ahk_id " hwnd)
    catch {
        return false
    }
    return (exStyle & 0x8) != 0
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

; 读取窗口的 DWM cloak 状态。
; 入参：hwnd。
; 出参：0 表示未 cloak；非 0 表示被 cloak，并携带原因位掩码。
; 背景说明：
; - Windows 官方 `DWMWA_CLOAKED` 属性可告诉我们“窗口当前为什么不可被用户看到”。
; - 其中 `DWM_CLOAKED_SHELL` 是 Shell 主动 cloak 的情况，
;   这正是“窗口还活着，但现在不在当前虚拟桌面上”的重要信号。
; - 这里先走一个成本很低的本地 DWM 查询，只把它当成“像不像留在别的桌面”的判断信号。
ChatGptChromeGetWindowCloakedReason(hwnd) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return 0
    }

    cloakBuffer := Buffer(4, 0)
    hr := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", 14,
        "ptr", cloakBuffer.Ptr,
        "uint", cloakBuffer.Size,
        "int"
    )
    if (hr != 0) {
        return 0
    }
    return NumGet(cloakBuffer, 0, "uint")
}

; 纯逻辑辅助：根据“是否可见 + cloak 原因”判断，
; 当前这次热键是否有必要进入跨桌面补救路径。
; 入参：isVisible、cloakReason。
; 出参：true / false。
ChatGptChromeShouldAttemptDesktopRecall(isVisible, cloakReason) {
    return isVisible && (cloakReason != 0)
}

; 判断当前窗口是否疑似需要“跨虚拟桌面召回”。
; 入参：hwnd。
; 出参：true / false。
ChatGptChromeWindowNeedsDesktopRecall(hwnd) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }
    return ChatGptChromeShouldAttemptDesktopRecall(
        ChatGptChromeIsWindowVisible(hwnd),
        ChatGptChromeGetWindowCloakedReason(hwnd)
    )
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
    try {
        WinShow("ahk_id " hwnd)
        if ChatGptChromeIsWindowMinimized(hwnd) {
            WinRestore("ahk_id " hwnd)
        }
        if !ChatGptChromeIsWindowHandleUsable(hwnd) {
            return false
        }
        WinMove(rect["x"], rect["y"], rect["w"], rect["h"], "ahk_id " hwnd)
        if !ChatGptChromeApplyWindowProtections(hwnd, settings) {
            return false
        }
        WinActivate("ahk_id " hwnd)
        ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
        return true
    } catch {
        return false
    }
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

    ; Chrome app 新开时，可能会先按它自己的记忆恢复成一个更大的窗口，
    ; 无视我们命令行里传入的 `--window-size/--window-position`。
    ; 如果这里立刻保存当前实际尺寸，就会把用户之前手调好的小窗状态污染掉。
    ; 因此现在改成：窗口出现后，先强制移动到目标矩形，再保存状态。
    try WinMove(rect["x"], rect["y"], rect["w"], rect["h"], "ahk_id " hwnd)
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

; 尝试把“还活着、但当前不在本桌面的旧窗口”召回到当前桌面。
; 入参：hwnd、settings。
; 出参：true=召回成功；false=召回失败。
; 说明：
; 1) 这里彻底不再依赖额外 helper。
; 2) 用户现场已经证明：同一个窗口在“先收起再唤起”时，可以跨桌面复用。
; 3) 因此这里直接把“召回”收口成最朴素的 hide/show 流程：
;    先把旧实例收一下，再按当前桌面的目标矩形重新展开。
ChatGptChromeRecallWindowToCurrentDesktop(hwnd, settings) {
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }

    try WinHide("ahk_id " hwnd)
    catch {
        return false
    }
    Sleep(40)
    return ChatGptChromeShowManagedWindow(hwnd, settings)
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
    if (state["hasRect"]
        && state["savedWindowMode"] = settings["windowMode"]
        && state["rectPolicyVersion"] = g_ChatGptChromeStateRectPolicyVersion) {
        return ChatGptChromeNormalizeRect(Map(
            "x", state["x"],
            "y", state["y"],
            "w", state["w"],
            "h", state["h"]
        ))
    }

    workArea := ChatGptChromeGetMouseMonitorWorkArea()
    return ChatGptChromeBuildDefaultRectFromWorkArea(settings, workArea)
}

; 基于给定工作区构造默认小窗矩形。
; 入参：settings、workArea。
; 出参：Map(x, y, w, h)。
ChatGptChromeBuildDefaultRectFromWorkArea(settings, workArea) {
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
        "savedWindowMode", IsObject(settings) ? settings["windowMode"] : ChatGptChromeReadState(root)["savedWindowMode"],
        "rectPolicyVersion", g_ChatGptChromeStateRectPolicyVersion
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

; 从托盘菜单重置浮窗位置与大小。
; 入参：菜单事件参数自动传入，但本函数不使用。
; 出参：无。
; 行为：
; 1) 若当前已有受管窗口：直接把它移动到默认小窗尺寸并保存。
; 2) 若当前没有受管窗口：清掉旧矩形状态，下次 Alt+Space 会按默认小窗新开或恢复。
ChatGptChromeResetWindowPlacementFromTray(*) {
    settings := ChatGptChromeReadSettings()
    hwnd := ChatGptChromeResolveManagedWindow()

    if hwnd && ChatGptChromeIsWindowHandleUsable(hwnd) {
        try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        catch {
            hwnd := 0
        }
    }

    if hwnd && ChatGptChromeIsWindowHandleUsable(hwnd) {
        workArea := ChatGptChromeGetWorkAreaForRect(Map("x", x, "y", y, "w", w, "h", h))
        rect := ChatGptChromeBuildDefaultRectFromWorkArea(settings, workArea)
        try {
            WinMove(rect["x"], rect["y"], rect["w"], rect["h"], "ahk_id " hwnd)
            ChatGptChromeApplyWindowProtections(hwnd, settings)
            ChatGptChromeSaveWindowPlacement(hwnd, "", settings)
            Toast("已重置 ChatGPT 浮窗位置与大小")
            return
        } catch {
            ChatGptChromeForgetManagedWindow()
        }
    }

    state := Map(
        "lastHwnd", 0,
        "x", 0,
        "y", 0,
        "w", 0,
        "h", 0,
        "savedWindowMode", settings["windowMode"],
        "rectPolicyVersion", 0
    )
    ChatGptChromeWriteState(state)
    Toast("已清空 ChatGPT 浮窗位置状态；下次将按默认小窗恢复。")
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
; - 只有当状态文件里的 `rect_policy_version` 与当前代码一致时，
;   旧矩形才会继续被信任；这样当我们改变“小窗策略”时，
;   可以一次性淘汰历史上的不合理旧尺寸。
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
    if !ChatGptChromeIsWindowHandleUsable(hwnd) {
        return false
    }
    try {
        if settings["alwaysOnTop"] {
            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        }
        if !ChatGptChromeIsWindowHandleUsable(hwnd) {
            return false
        }
        if settings["disableCloseButton"] {
            return ChatGptChromeSetCloseButtonEnabled(hwnd, false)
        }
        return ChatGptChromeSetCloseButtonEnabled(hwnd, true)
    } catch {
        return false
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
