#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off
; Task Scheduler 不能直接 CreateProcess 启动 *_UIA.exe。
; 这个一次性普通权限 bootstrap 通过 AutoHotkey 官方 *UIAccess Shell verb 拉起主脚本，然后立即退出。
mainScript := A_ScriptDir "\..\main.ahk"
Run('*UIAccess "' mainScript '"')
ExitApp
