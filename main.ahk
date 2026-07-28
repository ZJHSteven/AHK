#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================
; 入口脚本：
; - 加载所有模块（共用一个解释器进程）
; - 启动“沙盒下载夹监视并搬运”任务
; ============================================

; 让相对路径以本脚本所在目录为基准
SetWorkingDir A_ScriptDir

; CI / 本地回归可用的无副作用语法校验入口。
; AHK 会在执行前解析本文件及所有 #Include，因此立刻退出仍能覆盖主脚本和模块语法；
; 同时避免过去把 `/Validate` 当普通参数传入、意外额外启动一套定时 watcher。
if (A_Args.Length = 1 && A_Args[1] = "/Validate") {
    ExitApp
}

; ---- 引入模块 ----
#Include modules\utils.ahk
#Include modules\codex_profile_switcher.ahk
#Include modules\codex_desktop_patch_watcher.ahk
#Include modules\chatgpt_chrome_window.ahk
#Include modules\hotkey_help.ahk
#Include modules\hotkeys.ahk
#Include modules\window_switch.ahk
;#Include modules\llc_hold_speed.ahk
; #Include modules\watch_downloads.ahk

; ---- 初始化托盘菜单 ----
; 这里统一挂载“查看热键”和“Codex 预设切换”入口。
; 具体菜单内容放在独立模块里，main.ahk 只负责启动阶段组装。
AhkToolkitInitializeTrayMenu()

; 每分钟检查一次 Microsoft Store 的 Codex 包版本；只有版本变化才重建本地补丁副本。
CodexDesktopPatchWatcherInitialize()

; ---- 启动监听：每 100ms 扫描一次，简单直接 ----
;StartSandboxWatch()

;Toast("🟢 AHK 已启动（沙盒下载夹自动搬运进行中）", 1500)
