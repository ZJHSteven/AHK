#Requires AutoHotkey v2.0
; 最小真实查询测试：不启动常驻定时器，也不触发重建，只验证版号查询可用。
#Include ..\modules\utils.ahk
#Include ..\modules\codex_desktop_patch_watcher.ahk

version := CodexDesktopPatchWatcherGetInstalledVersion()
if !RegExMatch(version, "^\d+\.\d+\.\d+\.\d+$") {
    throw Error("未获得有效 OpenAI.Codex Store 版本：" version)
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
} finally {
    ; 测试只删除自己刚创建的临时目录，不触及正式 runtime 或用户会话数据。
    if DirExist(testRoot) {
        DirDelete(testRoot, true)
    }
}

FileAppend("PASS: version=" version "; variants-ready boundary checks passed`n", "*")
