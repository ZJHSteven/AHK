#Requires AutoHotkey v2.0
; ============================================
; Codex Desktop Stage 1 watcher 真实构建入口冒烟测试
; --------------------------------------------
; 该测试不会启动或关闭 Desktop UI。当前版本 Stage 1 已存在时，构建器只做安全跳过，
; 随后重新生成 Stable-only 启动器；测试用于覆盖 AHK -> PowerShell 的真实引号、
; stdout/stderr 捕获、产物复查和状态 INI 原子重写，而不只检查命令字符串。
; ============================================
#Include ..\modules\utils.ahk
#Include ..\modules\codex_desktop_patch_watcher.ahk

; #Include 不会改变 A_ScriptDir；测试入口位于 tests，所以显式把正式运行路径指回仓库根。
global g_CodexDesktopPatchWatchStatePath := A_ScriptDir "\..\config\codex_desktop_patcher_watcher.ini"
global g_CodexDesktopPatchWatchLogPath := A_ScriptDir "\..\logs\codex_desktop_patch_watcher.log"

version := CodexDesktopPatchWatcherGetInstalledVersion()
if !RegExMatch(version, "^\d+\.\d+\.\d+\.\d+$") {
    throw Error("无法取得有效 Store 版本：" version)
}

result := CodexDesktopPatchWatcherBuildStage1(version, false)
if !result["ok"] {
    throw Error("真实 Stage 1 watcher 构建入口失败：" result["message"] "`n" result["detail"])
}
if !CodexDesktopPatchWatcherIsStage1Ready(version) {
    throw Error("构建入口返回成功后 Stage 1 仍未就绪：" version)
}
if CodexDesktopPatchWatcherReadLastBuiltVersion() != version {
    throw Error("成功构建后 watcher 状态版本没有更新：" version)
}
if !InStr(result["detail"], "Stage 1") {
    throw Error("构建输出没有被 AHK 完整捕获")
}

FileAppend("PASS: Stage 1 watcher integration version=" version "`n", "*")
; 显式结束测试解释器，避免被误认为第二个常驻 AHK 实例。
ExitApp(0)
