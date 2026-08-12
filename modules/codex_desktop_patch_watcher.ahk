; ============================================
; Microsoft Store Codex Desktop 版本监视与透明 Stage 1 Clone 重建
; --------------------------------------------
; 设计目标：
; 1. AHK 已经常驻，因此用它的 SetTimer 每分钟执行一次轻量版号查询。
; 2. 只有 Store 版本或 Stage 1 产物状态变化，才调用项目重建透明 Clone。
; 3. 不保留后台 PowerShell；每次查询启动一个极短的 NoProfile 子进程后立即退出。
; 4. 状态文件只保存已处理版本，不保存配置、认证或路径以外的敏感内容。
; ============================================

global g_CodexDesktopPatchWatchIntervalMs := 60000
global g_CodexDesktopPatchWatchStatePath := A_ScriptDir "\config\codex_desktop_patcher_watcher.ini"
global g_CodexDesktopPatchProjectRoot := "D:\Workspace\codex-desktop-patcher"
global g_CodexDesktopPatchWatchLogPath := A_ScriptDir "\logs\codex_desktop_patch_watcher.log"
global g_CodexDesktopPatchPowerShellPath := "C:\Program Files\PowerShell\7\pwsh.exe"
global g_CodexDesktopPatchRetryDelayMs := 1800000
global g_CodexDesktopPatchFailedVersion := ""
global g_CodexDesktopPatchNextRetryTick := 0
global g_CodexDesktopPatchLastNoticeKey := ""

; 只记录真正影响判断的事件，不把每分钟一次的正常轮询写成海量日志。
; 这个日志用于回答“到底是哪一步失败”，避免以后只能凭弹窗猜测。
CodexDesktopPatchWatcherLog(message) {
    global g_CodexDesktopPatchWatchLogPath

    SplitPath(g_CodexDesktopPatchWatchLogPath, , &directory)
    if !DirExist(directory) {
        DirCreate(directory)
    }
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " message "`n", g_CodexDesktopPatchWatchLogPath, "UTF-8")
}

; 同一版本构建失败后暂缓重试，避免每分钟重复做一次昂贵构建并反复提示。
; A_TickCount 是系统启动后的毫秒数；本函数只处理 30 分钟这种短窗口。
CodexDesktopPatchWatcherShouldDelayRetry(version, currentTick := unset) {
    global g_CodexDesktopPatchFailedVersion
    global g_CodexDesktopPatchNextRetryTick

    if !IsSet(currentTick) {
        currentTick := A_TickCount
    }
    return version = g_CodexDesktopPatchFailedVersion && currentTick < g_CodexDesktopPatchNextRetryTick
}

; 保存失败退避状态，并返回本次是否需要向用户显示一条新提示。
; 完全相同的“版本 + 错误”只提示一次，但每次失败仍会落盘到日志。
CodexDesktopPatchWatcherRecordFailure(version, message, currentTick := unset) {
    global g_CodexDesktopPatchRetryDelayMs
    global g_CodexDesktopPatchFailedVersion
    global g_CodexDesktopPatchNextRetryTick
    global g_CodexDesktopPatchLastNoticeKey

    if !IsSet(currentTick) {
        currentTick := A_TickCount
    }
    g_CodexDesktopPatchFailedVersion := version
    g_CodexDesktopPatchNextRetryTick := currentTick + g_CodexDesktopPatchRetryDelayMs

    noticeKey := version "|" message
    shouldNotify := noticeKey != g_CodexDesktopPatchLastNoticeKey
    g_CodexDesktopPatchLastNoticeKey := noticeKey
    return shouldNotify
}

; 构建成功后清空失败状态，让未来真正的新版本可以正常触发。
CodexDesktopPatchWatcherClearFailure() {
    global g_CodexDesktopPatchFailedVersion
    global g_CodexDesktopPatchNextRetryTick
    global g_CodexDesktopPatchLastNoticeKey

    g_CodexDesktopPatchFailedVersion := ""
    g_CodexDesktopPatchNextRetryTick := 0
    g_CodexDesktopPatchLastNoticeKey := ""
}

; 初始化入口：启动后先尽快检查一次，之后每分钟检查。
CodexDesktopPatchWatcherInitialize() {
    global g_CodexDesktopPatchWatchIntervalMs

    CodexDesktopPatchWatcherLog("watcher 已启动")
    SetTimer(CodexDesktopPatchWatcherTick, -1500)
    SetTimer(CodexDesktopPatchWatcherTick, g_CodexDesktopPatchWatchIntervalMs)
}

; 查询当前用户已安装的 Microsoft Store Codex 包版本。
; 使用临时文件承接 PowerShell 标准输出，避免把复杂引号和管道逻辑塞进 AHK 变量。
; 即使调用方意外传入带换行的文本，也统一在这里规范化，避免版本号污染路径和 INI。
CodexDesktopPatchWatcherNormalizeVersion(rawVersion) {
    return Trim(rawVersion, " `t`r`n")
}

CodexDesktopPatchWatcherGetInstalledVersion() {
    tempPath := A_Temp "\codex_desktop_package_version_" A_TickCount ".txt"
    quote := Chr(34)
    ; -NoNewline 从源头避免 CRLF；NormalizeVersion 是第二道防线，兼容旧临时文件或命令变化。
    command := "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " quote "(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Version) | Set-Content -LiteralPath '" tempPath "' -Encoding ascii -NoNewline" quote

    try {
        exitCode := RunWait(command, , "Hide")
        if (exitCode != 0 || !FileExist(tempPath)) {
            return ""
        }
        return CodexDesktopPatchWatcherNormalizeVersion(FileRead(tempPath, "UTF-8"))
    } finally {
        try FileDelete(tempPath)
    }
}

; 读取上次已经成功构建过的 Store 包版本。
CodexDesktopPatchWatcherReadLastBuiltVersion() {
    global g_CodexDesktopPatchWatchStatePath
    return IniRead(g_CodexDesktopPatchWatchStatePath, "state", "last_built_version", "")
}

; 仅在 Stage 1 完整验收后写入版本，避免失败后被错误标记为已处理。
; 旧 INI 曾经累积多个重复 [state]；这里直接原子重写唯一 section，而不是继续 IniWrite。
CodexDesktopPatchWatcherWriteLastBuiltVersion(version) {
    global g_CodexDesktopPatchWatchStatePath
    SplitPath(g_CodexDesktopPatchWatchStatePath, , &directory)
    if !DirExist(directory) {
        DirCreate(directory)
    }
    tempPath := g_CodexDesktopPatchWatchStatePath ".tmp"
    try {
        if FileExist(tempPath) {
            FileDelete(tempPath)
        }
        FileAppend("[state]`nlast_built_version=" version "`n", tempPath, "UTF-8-RAW")
        FileMove(tempPath, g_CodexDesktopPatchWatchStatePath, true)
    } finally {
        try FileDelete(tempPath)
    }
}

; 判断某个 Store 版本的透明 Stage 1 是否真的完整落盘。
; manifest 必须明确声明 transparent-shim-stage1 和当前版本；仅有几个占位文件不能通过。
; runtimeRoot 参数主要给自动化测试使用；日常运行不传时使用正式 runtime 目录。
CodexDesktopPatchWatcherIsStage1Ready(version, runtimeRoot := "") {
    global g_CodexDesktopPatchProjectRoot

    if (runtimeRoot = "") {
        runtimeRoot := g_CodexDesktopPatchProjectRoot "\runtime"
    }

    stageRoot := runtimeRoot "\apps\OpenAI.Codex_" version "\stage1"
    appRoot := stageRoot "\app"
    manifestPath := stageRoot "\stage1-manifest.json"
    requiredPaths := [
        appRoot "\ChatGPT.exe",
        appRoot "\resources\app.asar",
        appRoot "\resources\codex.exe",
        appRoot "\resources\codex-real.exe",
        appRoot "\resources\codex-command-runner.exe",
        appRoot "\resources\codex-windows-sandbox-setup.exe",
        appRoot "\resources\codex-code-mode-host.exe",
        appRoot "\resources\rg.exe",
        manifestPath
    ]

    for requiredPath in requiredPaths {
        if !FileExist(requiredPath) {
            return false
        }
    }
    try {
        manifest := FileRead(manifestPath, "UTF-8")
    } catch {
        return false
    }
    escapedVersion := StrReplace(version, ".", "\.")
    hasArchitecture := RegExMatch(manifest, '"architecture"\s*:\s*"transparent-shim-stage1"')
    hasVersion := RegExMatch(manifest, '"packageVersion"\s*:\s*"' escapedVersion '"')
    hasProtocolCheck := RegExMatch(manifest, '"protocolValidation"\s*:\s*"initialize-direct-equals-shim"')
    return hasArchitecture && hasVersion && hasProtocolCheck
}

; 生成可测试的 PowerShell 命令：只构建 Stage 1，再生成 Stable-only 启动器。
; 整个 script block 的 stdout/stderr 都重定向到专属文件，AHK 日志会完整收录。
CodexDesktopPatchWatcherCreateBuildCommand(forceRebuild, outputPath) {
    global g_CodexDesktopPatchProjectRoot
    global g_CodexDesktopPatchPowerShellPath

    buildScript := g_CodexDesktopPatchProjectRoot "\scripts\Build-CodexDesktopStage1.ps1"
    launcherScript := g_CodexDesktopPatchProjectRoot "\scripts\New-CodexDesktopLaunchers.ps1"

    quote := Chr(34)
    forceRebuildArgument := forceRebuild ? " -ForceRebuild" : ""
    scriptBlock := "& { $ErrorActionPreference='Stop'; try { & '" buildScript "'" forceRebuildArgument "; & '" launcherScript "' -StableOnly; exit 0 } catch { Write-Error ($_ | Out-String); exit 1 } } *> '" outputPath "'"
    return quote g_CodexDesktopPatchPowerShellPath quote " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " quote scriptBlock quote
}

; 调用 Stage 1 构建链。失败与成功输出都会写入 watcher 日志，便于精确定位。
CodexDesktopPatchWatcherBuildStage1(version, forceRebuild := false) {
    global g_CodexDesktopPatchProjectRoot
    global g_CodexDesktopPatchPowerShellPath

    buildScript := g_CodexDesktopPatchProjectRoot "\scripts\Build-CodexDesktopStage1.ps1"
    launcherScript := g_CodexDesktopPatchProjectRoot "\scripts\New-CodexDesktopLaunchers.ps1"
    if !(FileExist(buildScript) && FileExist(launcherScript)) {
        return Map("ok", false, "message", "找不到 Stage 1 构建或启动器脚本", "detail", g_CodexDesktopPatchProjectRoot)
    }
    if !FileExist(g_CodexDesktopPatchPowerShellPath) {
        return Map("ok", false, "message", "找不到 PowerShell 7", "detail", g_CodexDesktopPatchPowerShellPath)
    }

    outputPath := A_Temp "\codex_desktop_stage1_build_" A_TickCount ".log"
    command := CodexDesktopPatchWatcherCreateBuildCommand(forceRebuild, outputPath)
    try {
        exitCode := RunWait(command, g_CodexDesktopPatchProjectRoot, "Hide")
        detail := FileExist(outputPath) ? FileRead(outputPath, "UTF-8") : "（构建进程没有生成输出文件）"
    } finally {
        try FileDelete(outputPath)
    }
    CodexDesktopPatchWatcherLog("Stage 1 构建输出：version=" version "; exit=" exitCode "`n" detail)
    if (exitCode != 0) {
        return Map("ok", false, "message", "Stage 1 构建脚本退出码：" exitCode, "detail", detail)
    }

    if !CodexDesktopPatchWatcherIsStage1Ready(version) {
        return Map("ok", false, "message", "构建结束但 Stage 1 manifest 或必要文件不完整", "detail", detail)
    }

    CodexDesktopPatchWatcherWriteLastBuiltVersion(version)
    return Map("ok", true, "message", "已重建透明 Stage 1 " version, "detail", detail)
}

; 定时回调：版本号与实际产物必须同时满足，才允许跳过。
CodexDesktopPatchWatcherTick() {
    version := CodexDesktopPatchWatcherGetInstalledVersion()
    if (version = "") {
        return
    }

    lastVersion := CodexDesktopPatchWatcherReadLastBuiltVersion()
    stage1Ready := CodexDesktopPatchWatcherIsStage1Ready(version)
    if (version = lastVersion && stage1Ready) {
        return
    }

    if CodexDesktopPatchWatcherShouldDelayRetry(version) {
        return
    }

    ; 首次运行也必须构建。若 INI 声称当前版本已处理、但目录不完整，
    ; 则强制重建该版本，修复状态文件领先于实际 runtime 的情况。
    result := CodexDesktopPatchWatcherBuildStage1(version, !stage1Ready)
    if result["ok"] {
        CodexDesktopPatchWatcherClearFailure()
        CodexDesktopPatchWatcherLog("构建成功：version=" version "; message=" result["message"])
        Toast("Codex Desktop 已更新，透明 Stage 1 已重建：" version, 4000)
    } else {
        CodexDesktopPatchWatcherLog("构建失败：version=" version "; message=" result["message"])
        if CodexDesktopPatchWatcherRecordFailure(version, result["message"]) {
            Toast("Codex Desktop 更新后重建失败：" result["message"] "（已暂停重复重试 30 分钟，详情见 watcher 日志）", 6000)
        }
    }
}
