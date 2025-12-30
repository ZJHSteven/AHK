#Include utils.ahk
; ============================================
; 你的热键集合（保持与你原脚本的功能一致）
; ============================================
; 自提权
if !A_IsAdmin {
    Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}


; Ctrl + Alt + Space -> 优先控制 Spotify 播放/暂停；否则发全局多媒体键
^!Space:: {
    if !SendSpotifyCommand(14) {
        ; Spotify 不在，就当普通播放/暂停键用
        Send("{Media_Play_Pause}")
    }
}

; Ctrl + Alt + Left -> 优先控制 Spotify 上一首；否则发全局上一首键
^!Left:: {
    if !SendSpotifyCommand(12) {
        Send("{Media_Prev}")
    }
}

; Ctrl + Alt + Right -> 优先控制 Spotify 下一首；否则发全局下一首键
^!Right:: {
    if !SendSpotifyCommand(11) {
        Send("{Media_Next}")
    }
}

; Ctrl + Shift + C → 去换行复制（先复制，再把 CR/LF 都去掉）
; 只有「当前活动窗口不是 Windows Terminal」时，
; 才启用 Ctrl+Shift+C 这个去换行复制热键
#HotIf !WinActive("ahk_exe WindowsTerminal.exe")
$^+c:: {
    Send("^c")
    Sleep(150)
    if !ClipWait(1) {
        Toast("❌ 剪贴板超时")
        return
    }
    text := A_Clipboard
    text := StrReplace(text, "`r")  ; 去 CR
    text := StrReplace(text, "`n")  ; 去 LF
    A_Clipboard := text
    Toast("✅ 已去换行并复制")
}
#HotIf

; 鼠标前进键 → 复制
XButton2:: {
    Send("^c")
}

; 鼠标后退键 → 粘贴
XButton1:: {
    Send("^v")
}

; Left Ctrl + Space → 回车（<^ 表示只用左 Ctrl）
<^Space:: {
    Send("{Enter}")
}
; Win+Alt+D：一键结束 WPS 相关进程
#!D::
{
    ; 用完整路径更稳：32/64位 AHK 都能找到 PowerShell
    pwsh := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"

    ps := "Get-Process | Where-Object { $_.Path -and ($_.Path -match 'Kingsoft|WPS Office') } "
        . "| Stop-Process -Force -PassThru | Select-Object Name, Id, Path"

    ; 将 ps 作为 -Command 的整体用双引号包起来（用 Chr(34) 拼接）
    cmd := pwsh " -NoProfile -ExecutionPolicy Bypass -Command " Chr(34) ps Chr(34)

    Run(cmd, , "Hide")  ; v2 正确写法
    Sleep(1000)
    Run(cmd, , "Hide")  ; 再来一次
    Toast("已尝试结束 WPS 相关进程。未保存的文档可能已被关闭。")
}
  
  
  
  
; 小工具函数：给 Spotify 发一个 WM_APPCOMMAND 命令
; appCommand 是命令编号：
;   14 = 播放/暂停
;   11 = 下一首
;   12 = 上一首
SendSpotifyCommand(appCommand) {
    hwnd := WinExist("ahk_exe Spotify.exe")
    if !hwnd {
        ; 找不到 Spotify 窗口，返回 false，让外面走“退而求其次”的逻辑
        return false
    }

    WM_APPCOMMAND := 0x0319
    ; lParam 高 16 位是命令编号
    DllCall(
        "SendMessage",
        "ptr", hwnd,
        "uint", WM_APPCOMMAND,
        "ptr", 0,
        "ptr", appCommand << 16
    )
    return true
}
