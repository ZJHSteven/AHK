#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================
; 入口脚本：
; - 加载所有模块（共用一个解释器进程）
; - 启动“沙盒下载夹监视并搬运”任务
; ============================================

; 让相对路径以本脚本所在目录为基准
SetWorkingDir A_ScriptDir

; ---- 引入模块 ----
#Include modules\utils.ahk
#Include modules\hotkeys.ahk
#Include modules\window_switch.ahk
#Include modules\watch_downloads.ahk

; ---- 启动监听：每 1000ms 扫描一次，轻量、稳定 ----
; （如需更省电，改成 1500~3000 也行；如需更快出结果，可改 500）
StartSandboxWatch(1000)

Toast("🟢 AHK 已启动（沙盒下载夹自动搬运进行中）", 1500)
