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
if !CodexDesktopPatchWatcherAreVariantsReady(version) {
    throw Error("真实 Store 版本的 stable/no-lock 正式产物当前不完整：" version)
}

; 使用专属临时目录验证“状态号不能代替产物”的核心边界：
; 没有文件、只有 stable、两个变体都完整，必须分别返回 false / false / true。
testRoot := A_Temp "\codex_desktop_patch_watcher_tests_" A_TickCount
testVersion := "99.88.77.66"
try {
    if CodexDesktopPatchWatcherAreVariantsReady(testVersion, testRoot) {
        throw Error("空 runtime 不应被判定为已构建")
    }

    stableApp := testRoot "\apps\OpenAI.Codex_" testVersion "\stable\app"
    DirCreate(stableApp "\resources")
    FileAppend("test", stableApp "\ChatGPT.exe")
    FileAppend("test", stableApp "\resources\app.asar")
    if CodexDesktopPatchWatcherAreVariantsReady(testVersion, testRoot) {
        throw Error("仅 stable 完整时不应被判定为已构建")
    }

    noLockApp := testRoot "\apps\OpenAI.Codex_" testVersion "\no-lock\app"
    DirCreate(noLockApp "\resources")
    FileAppend("test", noLockApp "\ChatGPT.exe")
    FileAppend("test", noLockApp "\resources\app.asar")
    if !CodexDesktopPatchWatcherAreVariantsReady(testVersion, testRoot) {
        throw Error("stable 与 no-lock 都完整时应被判定为已构建")
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

FileAppend("PASS: version=" version "; variants-ready and retry-debounce checks passed`n", "*")
