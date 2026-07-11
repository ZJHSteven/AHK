#Requires AutoHotkey v2.0
; 最小真实查询测试：不启动常驻定时器，也不触发重建，只验证版号查询可用。
#Include ..\modules\utils.ahk
#Include ..\modules\codex_desktop_patch_watcher.ahk

version := CodexDesktopPatchWatcherGetInstalledVersion()
if !RegExMatch(version, "^\d+\.\d+\.\d+\.\d+$") {
    throw Error("未获得有效 OpenAI.Codex Store 版本：" version)
}
FileAppend("PASS: " version "`n", "*")
