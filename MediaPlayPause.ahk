#Requires AutoHotkey v2.0

; ───── 迷你气泡函数 ─────
; 用系统托盘气泡；想完全静默，把 TrayTip 那行删掉。
Toast(msg, ms := 100) { 
    TrayTip "AutoHotkey", msg, ms
}

; Ctrl + Alt + Space → 媒体播放/暂停
^!Space:: Send "{Media_Play_Pause}"

; ───── 去换行复制 ─────
^!c::  ; Ctrl+Alt+C
{
    Send "^c"
    Sleep 150
    ClipWait 1
    text := A_Clipboard
    text := StrReplace(text, "`n", "")
    text := StrReplace(text, "`r", "")
    A_Clipboard := text
    Toast("✅ 已去换行并复制") ; 新增气泡提示
    return
}

XButton2::Send "^c"  ; 鼠标前进键 → 复制
XButton1:: Send "^v"  ; 鼠标后退键 → 粘贴
<^Space:: Send "{Enter}"  ; Ctrl+Space → 回车
; ─── 双击 Alt（300 ms 内）→ 右半屏下一个窗口 ───
~LAlt up:: {
    static last := 0, gap := 300
    if (A_TickCount - last < gap)
        CycleRightHalf()
    last := A_TickCount
}

ArrIndexOf(arr, val) {
    for i, v in arr
        if (v = val)
            return i
    return 0
}

CycleRightHalf() {
    ; ① 取主显示器工作区坐标
    MonitorGetWorkArea(1, &L, &T, &R, &B)   ; v2 专用
    midX := (L + R) // 2                    ; 屏幕中线

    ; ② 拿到当前桌面可见窗口的 Z 序
    winList := WinGetList()                 ; 顶→底
    active := WinGetID("A")
    rightWins := []

    for hwnd in winList {
        if WinGetMinMax(hwnd) = -1          ; 忽略最小化
            continue
        WinGetPos &x, , , , hwnd
        if (x >= midX)                      ; 只收右半屏
            rightWins.Push(hwnd)
    }

    if (rightWins.Length < 2)
        return                              ; 右边不足 2 窗，无需循环

    idx := ArrIndexOf(rightWins, active)    ; 当前排第几
    idx := idx ? (idx = rightWins.Length ? 1 : idx + 1) : 1
    WinActivate rightWins[idx]
}
