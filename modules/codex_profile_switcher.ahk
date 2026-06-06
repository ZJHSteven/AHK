; ============================================
; Codex 预设切换模块
; --------------------------------------------
; 这个模块只负责安全切换 Codex CLI 的本机配置文件：
; - live auth：%USERPROFILE%\.codex\auth.json
; - live config：%USERPROFILE%\.codex\config.toml
;
; 核心原则：
; 1) 真实密钥只放在 config/codex_profiles/secrets，且该目录被 .gitignore 忽略。
; 2) 切换前备份 live 文件，切换后做字节级比对确认。
; 3) Python 只在“首次校验或预设文件变化后”短暂启动，不常驻。
; 4) 所有成功/失败提示只走项目已有 Toast，也就是鼠标附近 ToolTip。
; ============================================

global g_CodexProfilesValidationRunCount := 0

; 计算项目根目录。
; 入参：无。
; 出参：项目根目录绝对路径。
CodexProfilesProjectRoot() {
    SplitPath(A_LineFile, , &moduleDir)
    return RegExReplace(moduleDir, "\\modules$")
}

; 计算预设根目录。
; 入参：
; - root：测试可传入临时根目录；为空时使用项目内 config/codex_profiles。
; 出参：预设根目录绝对路径。
CodexProfilesRoot(root := "") {
    if (root != "") {
        return root
    }
    return CodexProfilesProjectRoot() "\config\codex_profiles"
}

; 计算 live Codex 配置目录。
; 入参：
; - liveDir：测试可传入临时目录；为空时使用 %USERPROFILE%\.codex。
; 出参：live 配置目录绝对路径。
CodexProfilesLiveDir(liveDir := "") {
    if (liveDir != "") {
        return liveDir
    }
    return EnvGet("USERPROFILE") "\.codex"
}

; 确保预设目录结构存在，并尝试初始化第一套预设。
; 入参：可选 root / liveDir，测试时使用。
; 出参：无。
CodexProfilesEnsureLayout(root := "", liveDir := "") {
    root := CodexProfilesRoot(root)
    if !DirExist(root) {
        DirCreate(root)
    }
    if !DirExist(root "\secrets") {
        DirCreate(root "\secrets")
    }
    if !DirExist(root "\backups") {
        DirCreate(root "\backups")
    }

    CodexProfilesBootstrapFirstProfile(root, CodexProfilesLiveDir(liveDir))
}

; 首次启动时，把当前 live 配置复制到第一套预设。
; 入参：
; - root：预设根目录。
; - liveDir：Codex live 配置目录。
; 出参：true=执行或无需执行成功；false=缺 live 文件或复制失败。
CodexProfilesBootstrapFirstProfile(root, liveDir) {
    profiles := CodexProfilesLoadManifest(root)
    if (profiles.Length = 0) {
        return false
    }

    firstProfile := profiles[1]
    targetAuth := firstProfile["authPath"]
    targetConfig := firstProfile["configPath"]
    if (FileExist(targetAuth) && FileExist(targetConfig)) {
        return true
    }

    liveAuth := liveDir "\auth.json"
    liveConfig := liveDir "\config.toml"
    if !(FileExist(liveAuth) && FileExist(liveConfig)) {
        return false
    }

    try {
        SplitPath(targetAuth, , &authDir)
        SplitPath(targetConfig, , &configDir)
        if !DirExist(authDir) {
            DirCreate(authDir)
        }
        if !DirExist(configDir) {
            DirCreate(configDir)
        }
        if !FileExist(targetAuth) {
            FileCopy(liveAuth, targetAuth, false)
        }
        if !FileExist(targetConfig) {
            FileCopy(liveConfig, targetConfig, false)
        }
        return true
    } catch {
        return false
    }
}

; 读取 profiles.ini。
; 入参：预设根目录。
; 出参：预设数组；每项包含 id/displayName/authPath/configPath。
CodexProfilesLoadManifest(root := "") {
    root := CodexProfilesRoot(root)
    manifestPath := root "\profiles.ini"
    profiles := []

    if !FileExist(manifestPath) {
        return profiles
    }

    currentId := ""
    currentData := Map()
    fileText := FileRead(manifestPath, "UTF-8")
    lines := StrSplit(StrReplace(fileText, "`r", ""), "`n")

    for _, rawLine in lines {
        line := Trim(CodexProfilesStripInlineComment(rawLine), " `t")
        if (line = "") {
            continue
        }

        if RegExMatch(line, "^\[(.+)\]$", &sectionMatch) {
            CodexProfilesPushManifestEntry(profiles, root, currentId, currentData)
            currentId := Trim(sectionMatch[1], " `t")
            currentData := Map()
            continue
        }

        if (currentId = "") {
            continue
        }

        if RegExMatch(line, "^(.*?)\s*=\s*(.*)$", &kv) {
            key := StrLower(Trim(kv[1], " `t"))
            value := Trim(kv[2], " `t")
            currentData[key] := value
        }
    }

    CodexProfilesPushManifestEntry(profiles, root, currentId, currentData)
    return profiles
}

; 把当前 INI 分节转换成一条 profile 记录。
; 入参：profiles/root/currentId/currentData。
; 出参：无，直接追加 profiles。
CodexProfilesPushManifestEntry(profiles, root, currentId, currentData) {
    if (currentId = "") {
        return
    }

    displayName := currentData.Has("display_name") ? currentData["display_name"] : currentId
    authRel := currentData.Has("auth_path") ? currentData["auth_path"] : "secrets\" currentId "\auth.json"
    configRel := currentData.Has("config_path") ? currentData["config_path"] : "secrets\" currentId "\config.toml"

    profiles.Push(Map(
        "id", currentId,
        "displayName", displayName,
        "authPath", CodexProfilesResolvePath(root, authRel),
        "configPath", CodexProfilesResolvePath(root, configRel)
    ))
}

; 去掉 INI 行注释。
; 入参：单行文本。
; 出参：去掉 ; 或 # 后的内容。
CodexProfilesStripInlineComment(line) {
    trimmedLeft := LTrim(line, " `t")
    if (SubStr(trimmedLeft, 1, 1) = ";" || SubStr(trimmedLeft, 1, 1) = "#") {
        return ""
    }
    return line
}

; 把相对路径转换成绝对路径。
; 入参：
; - root：预设根目录。
; - pathText：相对或绝对路径。
; 出参：绝对路径。
CodexProfilesResolvePath(root, pathText) {
    if RegExMatch(pathText, "i)^[a-z]:\\|^\\\\") {
        return pathText
    }
    return root "\" pathText
}

; 查找指定 id 的 profile。
; 入参：profiles 数组、profileId。
; 出参：profile Map；找不到返回 0。
CodexProfilesFindById(profiles, profileId) {
    for _, profile in profiles {
        if (profile["id"] = profileId) {
            return profile
        }
    }
    return 0
}

; 判断某套预设是否已经配置完整。
; 入参：profile。
; 出参：true=auth/config 都存在且不是空文件。
CodexProfileIsConfigured(profile) {
    return FileExist(profile["authPath"])
        && FileExist(profile["configPath"])
        && FileGetSize(profile["authPath"]) > 0
        && FileGetSize(profile["configPath"]) > 0
}

; 生成一个用于判断“文件是否变化”的轻量指纹。
; 入参：profile。
; 出参：字符串，包含两个文件的大小和修改时间。
CodexProfileBuildStamp(profile) {
    return CodexProfileFileStamp(profile["authPath"]) "|" CodexProfileFileStamp(profile["configPath"])
}

; 生成单文件轻量指纹。
; 入参：文件路径。
; 出参：大小 + 修改时间；文件不存在时返回 missing。
CodexProfileFileStamp(path) {
    if !FileExist(path) {
        return "missing"
    }
    return FileGetSize(path) ":" FileGetTime(path, "M")
}

; 检查预设是否需要重新校验。
; 入参：
; - profile：预设记录。
; - statePath：缓存文件路径。
; 出参：true=需要启动 Python 校验。
CodexProfileNeedsValidation(profile, statePath) {
    stamp := CodexProfileBuildStamp(profile)
    section := "profile." profile["id"]
    oldStamp := IniRead(statePath, section, "stamp", "")
    oldValid := IniRead(statePath, section, "valid", "0")
    return !(oldStamp = stamp && oldValid = "1")
}

; 按需校验预设文件。
; 入参：
; - profile：预设记录。
; - root：预设根目录，用于定位 state.ini 和 helper。
; - force：true 时忽略缓存强制校验。
; 出参：Map("ok", bool, "message", 文本)。
CodexProfileValidateIfNeeded(profile, root := "", force := false) {
    root := CodexProfilesRoot(root)
    statePath := root "\state.ini"
    section := "profile." profile["id"]

    if !CodexProfileIsConfigured(profile) {
        return Map("ok", false, "message", "预设文件未配置完整")
    }

    if (!force && !CodexProfileNeedsValidation(profile, statePath)) {
        return Map("ok", true, "message", "已使用缓存校验结果")
    }

    result := CodexProfileRunPythonValidation(profile["authPath"], profile["configPath"])
    stamp := CodexProfileBuildStamp(profile)

    if result["ok"] {
        IniWrite(stamp, statePath, section, "stamp")
        IniWrite("1", statePath, section, "valid")
        IniWrite(A_Now, statePath, section, "validated_at")
        IniWrite("", statePath, section, "error")
        return Map("ok", true, "message", "JSON/TOML 校验通过")
    }

    IniWrite(stamp, statePath, section, "stamp")
    IniWrite("0", statePath, section, "valid")
    IniWrite(A_Now, statePath, section, "validated_at")
    IniWrite(result["message"], statePath, section, "error")
    return result
}

; 启动一次 Python helper，校验 auth.json 和 config.toml。
; 入参：两个文件路径。
; 出参：Map("ok", bool, "message", 文本)。
CodexProfileRunPythonValidation(authPath, configPath) {
    global g_CodexProfilesValidationRunCount
    g_CodexProfilesValidationRunCount += 1

    helperPath := CodexProfilesProjectRoot() "\tools\validate_codex_profile.py"
    outputPath := A_Temp "\ahk_codex_profile_validate_" A_TickCount ".txt"
    command := "python " CodexProfilesQuoteArg(helperPath) " "
        . CodexProfilesQuoteArg(authPath) " "
        . CodexProfilesQuoteArg(configPath) " > "
        . CodexProfilesQuoteArg(outputPath) " 2>&1"

    exitCode := RunWait(A_ComSpec " /C " command, , "Hide")
    output := FileExist(outputPath) ? Trim(FileRead(outputPath, "UTF-8"), " `t`r`n") : ""
    try FileDelete(outputPath)

    if (exitCode = 0) {
        return Map("ok", true, "message", "校验通过")
    }
    if (output = "") {
        output := "Python 校验失败，退出码 " exitCode
    }
    return Map("ok", false, "message", output)
}

; Windows 命令行参数加引号。
; 入参：原始参数。
; 出参：安全加引号后的参数。
CodexProfilesQuoteArg(value) {
    return Chr(34) StrReplace(value, Chr(34), Chr(92) Chr(34)) Chr(34)
}

; 检测当前 live 配置与哪套预设完全一致。
; 入参：root/liveDir 可选，测试时传临时目录。
; 出参：匹配到的 profile id；无匹配返回空字符串。
CodexProfilesDetectActiveId(root := "", liveDir := "") {
    match := CodexProfilesDetectActiveMatch(root, liveDir)
    if IsObject(match) {
        return match["id"]
    }
    return ""
}

; 检测 live 当前最像哪套预设。
; 入参：root/liveDir 可选，测试时传临时目录。
; 出参：
; - 命中时返回 Map("id", id, "profile", profileMap, "matchMode", "exact|config_only")。
; - 未命中时返回 0。
; 说明：
; 1) exact：auth.json 与 config.toml 都完全一致。
; 2) config_only：只允许“config 一致，但 auth 因 refresh token 自动刷新而漂移”的场景。
;    这样离开 OpenAI Official 前，脚本仍能认出当前 live 来自哪套预设，
;    进而先把最新 auth.json 回写到 secrets，避免下次切回旧 token。
CodexProfilesDetectActiveMatch(root := "", liveDir := "") {
    root := CodexProfilesRoot(root)
    liveDir := CodexProfilesLiveDir(liveDir)
    liveAuth := liveDir "\auth.json"
    liveConfig := liveDir "\config.toml"
    configOnlyMatches := []

    if !(FileExist(liveAuth) && FileExist(liveConfig)) {
        return 0
    }

    for _, profile in CodexProfilesLoadManifest(root) {
        if !CodexProfileIsConfigured(profile) {
            continue
        }

        authEqual := CodexProfilesFilesEqual(liveAuth, profile["authPath"])
        configEqual := CodexProfilesFilesEqual(liveConfig, profile["configPath"])

        if (authEqual && configEqual) {
            return Map("id", profile["id"], "profile", profile, "matchMode", "exact")
        }
        if configEqual {
            configOnlyMatches.Push(profile)
        }
    }

    if (configOnlyMatches.Length = 1) {
        profile := configOnlyMatches[1]
        return Map("id", profile["id"], "profile", profile, "matchMode", "config_only")
    }
    return 0
}

; 字节级比较两个文件是否完全一致。
; 入参：两个文件路径。
; 出参：true=大小与每个字节都一致。
CodexProfilesFilesEqual(pathA, pathB) {
    if !(FileExist(pathA) && FileExist(pathB)) {
        return false
    }
    if (FileGetSize(pathA) != FileGetSize(pathB)) {
        return false
    }

    bufA := FileRead(pathA, "RAW")
    bufB := FileRead(pathB, "RAW")
    loop bufA.Size {
        offset := A_Index - 1
        if (NumGet(bufA, offset, "UChar") != NumGet(bufB, offset, "UChar")) {
            return false
        }
    }
    return true
}

; 读取最后一次成功切换到哪套预设。
; 入参：root。
; 出参：命中的 profile Map；无记录或记录已失效时返回 0。
CodexProfilesReadLastSwitchProfile(root := "") {
    root := CodexProfilesRoot(root)
    statePath := root "\state.ini"
    profileId := IniRead(statePath, "last_switch", "profile_id", "")
    if (profileId = "") {
        return 0
    }

    profile := CodexProfilesFindById(CodexProfilesLoadManifest(root), profileId)
    if !IsObject(profile) {
        return 0
    }
    if !CodexProfileIsConfigured(profile) {
        return 0
    }
    return profile
}

; 解析“当前正在离开的来源预设”。
; 入参：
; - root/liveDir：预设根目录与 live 目录。
; - targetProfileId：本次要切入的目标预设 id，仅用于拼提示文案。
; 出参：
; - 命中时返回 Map("id", id, "profile", profileMap, "matchMode", "exact|config_only|last_switch")。
; - 未命中时返回 0。
; 设计取舍：
; 1) 托盘菜单里的“当前”标记仍只依赖保守的 DetectActiveMatch()，
;    避免用户把 live 改得面目全非后，菜单还误显示某套预设是当前态。
; 2) 但真正切换前的同步动作必须更激进：
;    只要 live 是从某套预设切出来并继续演化的，就应该尽量把整文件回写回去，
;    否则用户在运行时新装插件、改 provider、关 plugin 的变更都会被旧预设覆盖掉。
; 3) 因此这里先尝试 exact/config_only；若都失败，再退回到上次成功切换记录 last_switch。
CodexProfilesResolveSourceProfileForSync(root := "", liveDir := "", targetProfileId := "") {
    root := CodexProfilesRoot(root)
    liveDir := CodexProfilesLiveDir(liveDir)

    currentMatch := CodexProfilesDetectActiveMatch(root, liveDir)
    if IsObject(currentMatch) {
        return currentMatch
    }

    lastProfile := CodexProfilesReadLastSwitchProfile(root)
    if !IsObject(lastProfile) {
        return 0
    }

    return Map("id", lastProfile["id"], "profile", lastProfile, "matchMode", "last_switch")
}

; 在真正切换前，把当前 live auth.json 与 config.toml 整文件回写到“正在离开的那套预设”。
; 入参：
; - profile：来源预设；正常来自 CodexProfilesResolveSourceProfileForSync() 的结果。
; - liveDir：当前 live 目录。
; 出参：Map("ok", bool, "message", 文本)。
; 设计取舍：
; 1) 这里改为整文件同步 auth.json + config.toml。
;    原因是用户会在 live 运行态里真实安装/关闭插件、调整 provider / model / MCP，
;    如果只回写 auth，那么下一次切回预设时，旧 config.toml 会把这些 live 变更全部覆盖掉。
; 2) 回写前仍复用现有 Python helper 校验 live JSON/TOML，避免把损坏的 live 文件写回预设目录。
CodexProfilesSyncLiveFilesToProfile(profile, liveDir) {
    if !IsObject(profile) {
        return Map("ok", true, "message", "当前 live 未匹配任何预设，无需回写")
    }

    liveAuth := liveDir "\auth.json"
    liveConfig := liveDir "\config.toml"
    if !(FileExist(liveAuth) && FileExist(liveConfig)) {
        return Map("ok", false, "message", "当前 live auth.json / config.toml 不完整，无法回写来源预设")
    }

    validation := CodexProfileRunPythonValidation(liveAuth, liveConfig)
    if !validation["ok"] {
        return Map("ok", false, "message", "当前 live 配置校验失败，拒绝回写：" validation["message"])
    }

    SplitPath(profile["authPath"], , &authDir)
    SplitPath(profile["configPath"], , &configDir)
    if !DirExist(authDir) {
        DirCreate(authDir)
    }
    if !DirExist(configDir) {
        DirCreate(configDir)
    }

    try {
        FileCopy(liveAuth, profile["authPath"], true)
        FileCopy(liveConfig, profile["configPath"], true)
        if !(CodexProfilesFilesEqual(liveAuth, profile["authPath"])
            && CodexProfilesFilesEqual(liveConfig, profile["configPath"])) {
            throw Error("auth.json / config.toml 回写后比对失败")
        }
        return Map("ok", true, "message", "已同步来源预设整文件：" profile["displayName"])
    } catch as err {
        return Map("ok", false, "message", "回写来源预设整文件失败：" err.Message)
    }
}

; 切换到指定 Codex 预设。
; 入参：
; - profileId：profiles.ini 分节名。
; - root/liveDir：测试可覆盖路径。
; 出参：Map("ok", bool, "message", 文本, "backupDir", 路径)。
CodexProfilesSwitch(profileId, root := "", liveDir := "") {
    root := CodexProfilesRoot(root)
    liveDir := CodexProfilesLiveDir(liveDir)
    profiles := CodexProfilesLoadManifest(root)
    profile := CodexProfilesFindById(profiles, profileId)

    if !IsObject(profile) {
        return Map("ok", false, "message", "未找到预设：" profileId, "backupDir", "")
    }
    if !CodexProfileIsConfigured(profile) {
        return Map("ok", false, "message", profile["displayName"] " 未配置 auth.json / config.toml", "backupDir", "")
    }

    validation := CodexProfileValidateIfNeeded(profile, root)
    if !validation["ok"] {
        return Map("ok", false, "message", profile["displayName"] " 校验失败：" validation["message"], "backupDir", "")
    }

    sourceProfile := CodexProfilesResolveSourceProfileForSync(root, liveDir, profileId)
    if IsObject(sourceProfile) {
        syncResult := CodexProfilesSyncLiveFilesToProfile(sourceProfile["profile"], liveDir)
        if !syncResult["ok"] {
            return Map("ok", false, "message", syncResult["message"], "backupDir", "")
        }
    }

    backupDir := CodexProfilesBackupLive(root, liveDir)
    try {
        if !DirExist(liveDir) {
            DirCreate(liveDir)
        }
        FileCopy(profile["authPath"], liveDir "\auth.json", true)
        FileCopy(profile["configPath"], liveDir "\config.toml", true)

        if !(CodexProfilesFilesEqual(profile["authPath"], liveDir "\auth.json")
            && CodexProfilesFilesEqual(profile["configPath"], liveDir "\config.toml")) {
            throw Error("写入后比对失败")
        }

        CodexProfilesWriteLastSwitchState(root, profile)
        CodexProfilesPruneBackups(root, 20)
        return Map("ok", true, "message", "已切换到 " profile["displayName"], "backupDir", backupDir)
    } catch as err {
        CodexProfilesRestoreBackup(backupDir, liveDir)
        return Map("ok", false, "message", "切换失败，已尝试回滚：" err.Message, "backupDir", backupDir)
    }
}

; 写入最后一次成功切换状态。
; 入参：root/profile。
; 出参：无。
CodexProfilesWriteLastSwitchState(root, profile) {
    statePath := CodexProfilesRoot(root) "\state.ini"
    IniWrite(profile["id"], statePath, "last_switch", "profile_id")
    IniWrite(profile["displayName"], statePath, "last_switch", "display_name")
    IniWrite(A_Now, statePath, "last_switch", "switched_at")
}

; 切换前备份当前 live auth/config。
; 入参：root/liveDir。
; 出参：本次备份目录。
CodexProfilesBackupLive(root, liveDir) {
    backupRoot := CodexProfilesRoot(root) "\backups"
    if !DirExist(backupRoot) {
        DirCreate(backupRoot)
    }

    backupDir := backupRoot "\" FormatTime(A_Now, "yyyyMMdd-HHmmss") "-" A_TickCount
    DirCreate(backupDir)

    liveAuth := liveDir "\auth.json"
    liveConfig := liveDir "\config.toml"
    if FileExist(liveAuth) {
        FileCopy(liveAuth, backupDir "\auth.json", true)
    }
    if FileExist(liveConfig) {
        FileCopy(liveConfig, backupDir "\config.toml", true)
    }
    return backupDir
}

; 从备份目录恢复 live 文件。
; 入参：backupDir/liveDir。
; 出参：无。
CodexProfilesRestoreBackup(backupDir, liveDir) {
    if (backupDir = "" || !DirExist(backupDir)) {
        return
    }
    if !DirExist(liveDir) {
        DirCreate(liveDir)
    }

    if FileExist(backupDir "\auth.json") {
        FileCopy(backupDir "\auth.json", liveDir "\auth.json", true)
    }
    if FileExist(backupDir "\config.toml") {
        FileCopy(backupDir "\config.toml", liveDir "\config.toml", true)
    }
}

; 保留最近 limit 份备份，删除更旧目录。
; 入参：root/limit。
; 出参：无。
CodexProfilesPruneBackups(root := "", limit := 20) {
    backupRoot := CodexProfilesRoot(root) "\backups"
    if !DirExist(backupRoot) {
        return
    }

    names := ""
    count := 0
    Loop Files, backupRoot "\*", "D" {
        names .= A_LoopFileName "`n"
        count += 1
    }
    if (count <= limit) {
        return
    }

    sortedNames := Sort(RTrim(names, "`n"))
    removeCount := count - limit
    for _, name in StrSplit(sortedNames, "`n") {
        if (removeCount <= 0) {
            break
        }
        try DirDelete(backupRoot "\" name, true)
        removeCount -= 1
    }
}

; 构造托盘 Codex 预设子菜单。
; 入参：
; - root：预设根目录；正常运行时留空，自动使用 config/codex_profiles。
; - liveDir：Codex 当前生效目录；正常运行时留空，自动使用 %USERPROFILE%\.codex。
; 出参：Menu 对象。
CodexProfilesBuildTrayMenu(root := "", liveDir := "", *) {
    ; 注意：AutoHotkey 变量名不区分大小写。
    ; 如果这里把局部变量命名为 menu，表达式 menu := Menu() 会让右侧 Menu
    ; 被解释成“同一个还没赋值的局部变量”，而不是 AHK 内置 Menu 类。
    ; 所以这里必须使用 profileMenu 这类不会遮蔽内置类名的变量名。
    root := (root = "") ? CodexProfilesRoot() : root
    CodexProfilesEnsureLayout(root)
    activeId := CodexProfilesDetectActiveId(root, liveDir)
    profileMenu := Menu()

    for _, profile in CodexProfilesLoadManifest(root) {
        configured := CodexProfileIsConfigured(profile)
        label := ""
        if (profile["id"] = activeId) {
            label .= "[当前] "
        }
        label .= profile["displayName"]
        if !configured {
            label .= " [未配置]"
        }

        profileMenu.Add(label, CodexProfilesMakeSwitchHandler(profile["id"]))
        if !configured {
            profileMenu.Disable(label)
        }
    }

    profileMenu.Add()
    profileMenu.Add("打开预设目录", CodexProfilesOpenRoot)
    profileMenu.Add("校验全部预设", CodexProfilesValidateAllFromTray)
    return profileMenu
}

; 生成绑定 profileId 的菜单回调。
; 入参：profileId。
; 出参：回调函数对象。
CodexProfilesMakeSwitchHandler(profileId) {
    return (*) => CodexProfilesSwitchFromTray(profileId)
}

; 热键入口：在鼠标当前位置弹出 Codex 预设菜单。
; 入参：无。
; 出参：无。
CodexProfilesShowTrayMenu(*) {
    CodexProfilesBuildTrayMenu().Show()
}

; 托盘菜单切换入口，负责显示人类可读提示。
; 入参：profileId。
; 出参：无。
CodexProfilesSwitchFromTray(profileId) {
    result := CodexProfilesSwitch(profileId)
    if result["ok"] {
        Toast(result["message"] "。已写入并比对成功；请重启 Codex 终端后生效。", 2600)
    } else {
        Toast(result["message"], 3200)
    }
}

; 打开预设根目录。
; 入参：事件参数由菜单传入，本函数不使用。
; 出参：无。
CodexProfilesOpenRoot(*) {
    root := CodexProfilesRoot()
    CodexProfilesEnsureLayout(root)
    Run(root)
}

; 托盘入口：强制校验所有已配置预设。
; 入参：事件参数由菜单传入，本函数不使用。
; 出参：无。
CodexProfilesValidateAllFromTray(*) {
    root := CodexProfilesRoot()
    okCount := 0
    failCount := 0
    skippedCount := 0

    for _, profile in CodexProfilesLoadManifest(root) {
        if !CodexProfileIsConfigured(profile) {
            skippedCount += 1
            continue
        }
        result := CodexProfileValidateIfNeeded(profile, root, true)
        if result["ok"] {
            okCount += 1
        } else {
            failCount += 1
        }
    }

    Toast("Codex 预设校验完成：通过 " okCount "，失败 " failCount "，未配置 " skippedCount, 2600)
}
