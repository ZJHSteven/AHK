; ============================================
; Microsoft Store Codex Desktop 版本监视与补丁重建
; --------------------------------------------
; 设计目标：
; 1. AHK 已经常驻，因此用它的 SetTimer 每分钟执行一次轻量版号查询。
; 2. 只有 OpenAI.Codex 的 Store 包版本发生变化，才调用补丁项目重建两种副本。
; 3. 不保留后台 PowerShell；每次查询启动一个极短的 NoProfile 子进程后立即退出。
; 4. 状态文件只保存已处理版本，不保存配置、认证或路径以外的敏感内容。
; ============================================

global g_CodexDesktopPatchWatchIntervalMs := 60000
global g_CodexDesktopPatchWatchStatePath := A_ScriptDir "\config\codex_desktop_patcher_watcher.ini"
global g_CodexDesktopPatchProjectRoot := "D:\Workspace\codex-desktop-patcher"

; 初始化入口：启动后先尽快检查一次，之后每分钟检查。
CodexDesktopPatchWatcherInitialize() {
    global g_CodexDesktopPatchWatchIntervalMs

    SetTimer(CodexDesktopPatchWatcherTick, -1500)
    SetTimer(CodexDesktopPatchWatcherTick, g_CodexDesktopPatchWatchIntervalMs)
}

; 查询当前用户已安装的 Microsoft Store Codex 包版本。
; 使用临时文件承接 PowerShell 标准输出，避免把复杂引号和管道逻辑塞进 AHK 变量。
CodexDesktopPatchWatcherGetInstalledVersion() {
    tempPath := A_Temp "\codex_desktop_package_version_" A_TickCount ".txt"
    quote := Chr(34)
    command := "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " quote "(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Version) | Set-Content -LiteralPath '" tempPath "' -Encoding ascii" quote

    try {
        exitCode := RunWait(command, , "Hide")
        if (exitCode != 0 || !FileExist(tempPath)) {
            return ""
        }
        return Trim(FileRead(tempPath, "UTF-8"))
    } finally {
        try FileDelete(tempPath)
    }
}

; 读取上次已经成功构建过的 Store 包版本。
CodexDesktopPatchWatcherReadLastBuiltVersion() {
    global g_CodexDesktopPatchWatchStatePath
    return IniRead(g_CodexDesktopPatchWatchStatePath, "state", "last_built_version", "")
}

; 仅在两种副本都成功构建后写入版本，避免失败后被错误标记为已处理。
CodexDesktopPatchWatcherWriteLastBuiltVersion(version) {
    global g_CodexDesktopPatchWatchStatePath
    SplitPath(g_CodexDesktopPatchWatchStatePath, , &directory)
    if !DirExist(directory) {
        DirCreate(directory)
    }
    IniWrite(version, g_CodexDesktopPatchWatchStatePath, "state", "last_built_version")
}

; 调用独立 Git 仓库中的构建脚本。运行过程隐藏窗口，结束后用返回码决定是否写状态。
CodexDesktopPatchWatcherBuildVariants(version) {
    global g_CodexDesktopPatchProjectRoot

    buildScript := g_CodexDesktopPatchProjectRoot "\scripts\Build-CodexDesktop.ps1"
    launcherScript := g_CodexDesktopPatchProjectRoot "\scripts\New-CodexDesktopLaunchers.ps1"
    if !(FileExist(buildScript) && FileExist(launcherScript)) {
        return Map("ok", false, "message", "找不到 Codex Desktop 补丁项目脚本：" g_CodexDesktopPatchProjectRoot)
    }

    quote := Chr(34)
    command := "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " quote "& '" buildScript "' -Variant Stable; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & '" buildScript "' -Variant NoLock; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & '" launcherScript "'; exit $LASTEXITCODE" quote
    exitCode := RunWait(command, g_CodexDesktopPatchProjectRoot, "Hide")
    if (exitCode != 0) {
        return Map("ok", false, "message", "构建脚本退出码：" exitCode)
    }

    CodexDesktopPatchWatcherWriteLastBuiltVersion(version)
    return Map("ok", true, "message", "已重建 " version)
}

; 定时回调：首次运行只记录版本，避免 AHK 每次重启都无意义重打包。
CodexDesktopPatchWatcherTick() {
    version := CodexDesktopPatchWatcherGetInstalledVersion()
    if (version = "") {
        return
    }

    lastVersion := CodexDesktopPatchWatcherReadLastBuiltVersion()
    if (lastVersion = "") {
        CodexDesktopPatchWatcherWriteLastBuiltVersion(version)
        return
    }
    if (version = lastVersion) {
        return
    }

    result := CodexDesktopPatchWatcherBuildVariants(version)
    if result["ok"] {
        Toast("Codex Desktop 已更新，补丁副本已重建：" version, 4000)
    } else {
        Toast("Codex Desktop 更新后重建失败：" result["message"], 6000)
    }
}
