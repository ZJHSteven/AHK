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

; 判断某个 Store 版本的两个补丁变体是否真的都已经落盘。
; 不能只相信 INI 中的版本号：旧逻辑曾在首次检查时先写入版本、却没有构建，
; 因而需要把实际可启动程序和被补丁的 app.asar 都作为成功条件。
; runtimeRoot 参数主要给自动化测试使用；日常运行不传时使用正式 runtime 目录。
CodexDesktopPatchWatcherAreVariantsReady(version, runtimeRoot := "") {
    global g_CodexDesktopPatchProjectRoot

    if (runtimeRoot = "") {
        runtimeRoot := g_CodexDesktopPatchProjectRoot "\runtime"
    }

    versionRoot := runtimeRoot "\apps\OpenAI.Codex_" version
    requiredPaths := [
        versionRoot "\stable\app\ChatGPT.exe",
        versionRoot "\stable\app\resources\app.asar",
        versionRoot "\no-lock\app\ChatGPT.exe",
        versionRoot "\no-lock\app\resources\app.asar"
    ]

    for requiredPath in requiredPaths {
        if !FileExist(requiredPath) {
            return false
        }
    }
    return true
}

; 调用独立 Git 仓库中的构建脚本。运行过程隐藏窗口，结束后用返回码决定是否写状态。
; forceRebuild 仅在本应完成的版本缺少产物时使用，用于清理不完整的 runtime 目标。
CodexDesktopPatchWatcherBuildVariants(version, forceRebuild := false) {
    global g_CodexDesktopPatchProjectRoot

    buildScript := g_CodexDesktopPatchProjectRoot "\scripts\Build-CodexDesktop.ps1"
    launcherScript := g_CodexDesktopPatchProjectRoot "\scripts\New-CodexDesktopLaunchers.ps1"
    if !(FileExist(buildScript) && FileExist(launcherScript)) {
        return Map("ok", false, "message", "找不到 Codex Desktop 补丁项目脚本：" g_CodexDesktopPatchProjectRoot)
    }

    quote := Chr(34)
    ; 只在状态与实际目录不一致时传入强制重建，避免正常轮询误删可用副本。
    forceRebuildArgument := forceRebuild ? " -ForceRebuild" : ""
    command := "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " quote "& '" buildScript "' -Variant Stable" forceRebuildArgument "; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & '" buildScript "' -Variant NoLock" forceRebuildArgument "; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & '" launcherScript "'; exit $LASTEXITCODE" quote
    exitCode := RunWait(command, g_CodexDesktopPatchProjectRoot, "Hide")
    if (exitCode != 0) {
        return Map("ok", false, "message", "构建脚本退出码：" exitCode)
    }

    ; 脚本返回 0 仍不足以证明两个副本可启动；这里再次检查实际文件，
    ; 以免把失败或被跳过的构建错误记成“已经处理”。
    if !CodexDesktopPatchWatcherAreVariantsReady(version) {
        return Map("ok", false, "message", "构建结束但稳定版或 no-lock 产物缺失")
    }

    CodexDesktopPatchWatcherWriteLastBuiltVersion(version)
    return Map("ok", true, "message", "已重建 " version)
}

; 定时回调：版本号与实际产物必须同时满足，才允许跳过。
CodexDesktopPatchWatcherTick() {
    version := CodexDesktopPatchWatcherGetInstalledVersion()
    if (version = "") {
        return
    }

    lastVersion := CodexDesktopPatchWatcherReadLastBuiltVersion()
    variantsReady := CodexDesktopPatchWatcherAreVariantsReady(version)
    if (version = lastVersion && variantsReady) {
        return
    }

    ; 首次运行也必须构建。若 INI 声称当前版本已处理、但目录不完整，
    ; 则强制重建该版本，修复状态文件领先于实际 runtime 的情况。
    result := CodexDesktopPatchWatcherBuildVariants(version, !variantsReady)
    if result["ok"] {
        Toast("Codex Desktop 已更新，补丁副本已重建：" version, 4000)
    } else {
        Toast("Codex Desktop 更新后重建失败：" result["message"], 6000)
    }
}
