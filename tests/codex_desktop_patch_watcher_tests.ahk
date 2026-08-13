#Requires AutoHotkey v2.0
; 最小真实查询测试：不启动常驻定时器，也不触发重建，只验证版号查询可用。
#Include ..\modules\utils.ahk
#Include ..\modules\codex_desktop_patch_watcher.ahk

version := CodexDesktopPatchWatcherGetInstalledVersion()
if !RegExMatch(version, "^\d+\.\d+\.\d+\.\d+$") {
    throw Error("未获得有效 OpenAI.Codex Store 版本：" version)
}
if InStr(version, "`r") || InStr(version, "`n") {
    throw Error("Store 版本不得包含回车或换行")
}
if CodexDesktopPatchWatcherNormalizeVersion(" `t26.721.4979.0`r`n") != "26.721.4979.0" {
    throw Error("版本规范化必须同时移除空格、Tab、CR 和 LF")
}
if !FileExist(g_CodexDesktopPatchPowerShellPath) {
    throw Error("watcher 指定的 PowerShell 7 不存在：" g_CodexDesktopPatchPowerShellPath)
}
if !CodexDesktopPatchWatcherIsStage5Ready(version) {
    throw Error("真实 Store 版本的协议路由 Stage 5 正式产物当前不完整：" version)
}

; 使用专属临时目录验证“状态号不能代替产物”的核心边界。
testRoot := A_Temp "\codex_desktop_patch_watcher_tests_" A_TickCount
testVersion := "99.88.77.66"
try {
    if CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("空 runtime 不应被判定为已构建")
    }

    stageRoot := testRoot "\apps\OpenAI.Codex_" testVersion "\stage5"
    stageApp := stageRoot "\app"
    resources := stageApp "\resources"
    DirCreate(resources)
    requiredFiles := [
        stageApp "\ChatGPT.exe",
        resources "\app.asar",
        resources "\codex.exe",
        resources "\codex-real.exe",
        resources "\codex-shim-routes.json",
        resources "\codex-command-runner.exe",
        resources "\codex-windows-sandbox-setup.exe",
        resources "\codex-code-mode-host.exe",
        resources "\rg.exe"
    ]
    for requiredFile in requiredFiles {
        FileAppend("test", requiredFile)
    }
    hash64 := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    validManifest := '{"architecture":"protocol-observer-stage5","packageVersion":"' testVersion '","protocolValidation":"initialize-direct-equals-shim","realCliSha256":"' hash64 '","shimSha256":"' hash64 '","routesSha256":"' hash64 '","validatedVirtualModels":["heyiwei::gpt-5.6-sol","heyiwei::gpt-5.6-terra","deepseek-v4-flash"]}'
    FileAppend(StrReplace(validManifest, "protocol-observer-stage5", "wrong"), stageRoot "\stage5-manifest.json", "UTF-8")
    if CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("文件齐全但 architecture 错误时不应就绪")
    }
    FileDelete(stageRoot "\stage5-manifest.json")

    ; 即使 architecture 正确，版本、模型或哈希契约缺失也不能发布。
    FileAppend(StrReplace(validManifest, testVersion, "99.88.77.65"), stageRoot "\stage5-manifest.json", "UTF-8")
    if CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("manifest 版本与 Store 版本不一致时不应就绪")
    }
    FileDelete(stageRoot "\stage5-manifest.json")
    FileAppend(StrReplace(validManifest, '"deepseek-v4-flash"', '"missing-model"'), stageRoot "\stage5-manifest.json", "UTF-8")
    if CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("缺少任一已验收虚拟模型时不应就绪")
    }
    FileDelete(stageRoot "\stage5-manifest.json")
    FileAppend(StrReplace(validManifest, hash64, "SHORT", , , 1), stageRoot "\stage5-manifest.json", "UTF-8")
    if CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("manifest 缺少有效 64 位 SHA-256 时不应就绪")
    }
    FileDelete(stageRoot "\stage5-manifest.json")

    ; 完整 Stage 5 manifest 与必要文件齐全后才允许判定为可发布。
    FileAppend(validManifest, stageRoot "\stage5-manifest.json", "UTF-8")
    if !CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("文件、哈希、路由配置与 Stage 5 manifest 完整时应判定为已构建")
    }
    FileDelete(resources "\codex-real.exe")
    if CodexDesktopPatchWatcherIsStage5Ready(testVersion, testRoot) {
        throw Error("manifest 正确但任一必要文件缺失时不应就绪")
    }
    FileAppend("test", resources "\codex-real.exe")

    ; 构建命令必须发布 Stage 5 和 StableOnly，不能残留 Stage 4 或旧 NoLock 构建。
    command := CodexDesktopPatchWatcherCreateBuildCommand(true, testRoot "\build.log")
    if !InStr(command, "Build-CodexDesktopStage1.ps1") || !InStr(command, "-StageName stage5") || !InStr(command, "-PublishState") || !InStr(command, "-ForceRebuild") || !InStr(command, "-StableOnly") {
        throw Error("Stage 5 构建命令缺少必要入口或参数")
    }
    if InStr(command, "-StageName stage4") || InStr(command, "-Variant NoLock") {
        throw Error("Stage 5 watcher 不得回退构建 Stage 4 或 NoLock")
    }

    ; 状态写入必须清理重复 section，只留下一个规范化版本值。
    originalStatePath := g_CodexDesktopPatchWatchStatePath
    global g_CodexDesktopPatchWatchStatePath := testRoot "\watcher.ini"
    try {
        FileAppend("[state]`nlast_built_version=old`n[state]`nlast_built_version=older`n", g_CodexDesktopPatchWatchStatePath, "UTF-8")
        CodexDesktopPatchWatcherWriteLastBuiltVersion(testVersion)
        stateText := FileRead(g_CodexDesktopPatchWatchStatePath, "UTF-8")
        StrReplace(stateText, "[state]", "", false, &sectionCount)
        if sectionCount != 1 {
            throw Error("状态文件必须只保留一个 [state]")
        }
        if CodexDesktopPatchWatcherReadLastBuiltVersion() != testVersion {
            throw Error("状态文件回读版本不一致")
        }
    } finally {
        global g_CodexDesktopPatchWatchStatePath := originalStatePath
    }

    ; 同一失败在退避窗口内不得每分钟重试，也不得反复弹相同提示。
    global g_CodexDesktopPatchRetryDelayMs := 1800000
    CodexDesktopPatchWatcherClearFailure()
    if !CodexDesktopPatchWatcherRecordFailure(testVersion, "模拟失败", 1000) {
        throw Error("首次失败应允许提示")
    }
    if !CodexDesktopPatchWatcherShouldDelayRetry(testVersion, 1001) {
        throw Error("失败后 30 分钟内应暂停重试")
    }
    if CodexDesktopPatchWatcherRecordFailure(testVersion, "模拟失败", 2000) {
        throw Error("完全相同的失败不应重复提示")
    }
    if CodexDesktopPatchWatcherShouldDelayRetry("99.88.77.67", 2001) {
        throw Error("新版本不应继承旧版本的退避")
    }
    if CodexDesktopPatchWatcherShouldDelayRetry(testVersion, 1802001) {
        throw Error("退避期结束后应允许再次尝试")
    }
    CodexDesktopPatchWatcherClearFailure()
} finally {
    ; 测试只删除自己刚创建的临时目录，不触及正式 runtime 或用户会话数据。
    if DirExist(testRoot) {
        DirDelete(testRoot, true)
    }
}

FileAppend("PASS: version=" version "; stage5-ready, routing command, state and retry checks passed`n", "*")
; AutoHotkey 是 GUI 子系统；显式退出让 CI/PowerShell 能可靠等待测试结束，不遗留测试进程。
ExitApp(0)
