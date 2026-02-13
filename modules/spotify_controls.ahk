; ============================================
; Spotify 控制工具模块
; --------------------------------------------
; 这个模块只负责 Spotify 相关的窗口与媒体控制函数，
; 让 hotkeys.ahk 只保留“热键映射”与少量流程逻辑。
; ============================================

; 优先激活已有 Spotify 窗口，否则再启动 Spotify 协议。
; 关键顺序：
; 1) 先判断是否最小化（避免“最小化但仍被判定前台”的反复切换）。
; 2) 再判断是否当前前台窗口。
; 入参：无
; 返回：true=已找到并处理窗口，false=未找到窗口，仅触发启动
ActivateSpotifyToFront() {
    hwnd := WinExist("ahk_exe Spotify.exe")          ; 查找 Spotify 窗口句柄
    if hwnd {
        winState := WinGetMinMax("ahk_id " hwnd)     ; -1 最小化，0 正常，1 最大化
        if (winState = -1) {                         ; 最小化时：先还原再激活
            WinRestore("ahk_id " hwnd)
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            return true
        }
        if WinActive("ahk_id " hwnd) {               ; 已在前台：执行“收起”行为
            WinMinimize("ahk_id " hwnd)
            return true
        }
        WinRestore("ahk_id " hwnd)                   ; 非前台且非最小化：拉到前台
        WinShow("ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
        return true
    }
    Run("spotify:")                                  ; 未找到窗口：走协议启动
    return false
}

; 给 Spotify 发 WM_APPCOMMAND 命令。
; 常用命令：
; 14 = 播放/暂停，11 = 下一首，12 = 上一首
; 入参：appCommand（整数命令码）
; 返回：true=发送成功，false=未找到 Spotify 窗口
SendSpotifyCommand(appCommand) {
    hwnd := WinExist("ahk_exe Spotify.exe")
    if !hwnd {
        return false                                 ; 找不到窗口，让外层走兜底媒体键
    }

    WM_APPCOMMAND := 0x0319
    DllCall(
        "SendMessage",
        "ptr", hwnd,
        "uint", WM_APPCOMMAND,
        "ptr", 0,
        "ptr", appCommand << 16                     ; lParam 高 16 位放命令码
    )
    return true
}
