; ============================================
; “双击 Alt”智能切窗
; 逻辑：
;  ① 若有“几乎完全被挡住”的窗口 → 按 MRU 顺序翻出来
;  ② 否则在同侧窗口里循环
;  ③ 同侧不足 2 个 → 退化为系统 Alt-Tab
; ============================================

; ---------- 全局 ----------
global HiddenList := []        ; 记录“被挡住”的 hwnd
global MRU := []               ; 最近激活队列（Most-Recently-Used）
global MIN_RATIO := 0.25       ; 过滤掉宽或高 < 工作区 25% 的小窗
global COVER_THRESHOLD := 0.90 ; ≥90% 被遮认为“看不见”
global GAP := 300              ; Alt 双击间隔 ms

; ---------- 维护 MRU 队列 ----------
; WM_ACTIVATE：当前活动窗口变化时更新 MRU
OnMessage(0x0006, WM_ACTIVATE)
WM_ACTIVATE(wParam, lParam, msg, hwnd) {
    global MRU
    if !hwnd
        return
    idx := ArrIndexOf(MRU, hwnd)
    if (idx)
        MRU.RemoveAt(idx)
    MRU.InsertAt(1, hwnd)  ; 最近激活放最前
}

; ---------- 双击 Alt 触发 ----------
~LAlt up:: {
    static last := 0
    if (A_TickCount - last < GAP)
        SmartSwitch()
    last := A_TickCount
}

SmartSwitch() {
    UpdateHiddenList()

    ; ① 有被挡窗 → 按 MRU 顺序翻出来
    for hwnd in MRU
        if ArrIndexOf(HiddenList, hwnd) {
            ActivateAndRotateHidden(hwnd)
            return
        }

    if (HiddenList.Length) {
        ; 退而求其次
        ActivateAndRotateHidden(HiddenList[1])
        return
    }

    ; ② 无被挡窗 → 同侧循环 / Alt-Tab
    SameSideOrAltTab()
}

ActivateAndRotateHidden(hwnd) {
    WinActivate hwnd
    ; 把它挪到 HiddenList 尾部，形成循环
    idx := ArrIndexOf(HiddenList, hwnd)
    if (idx) {
        HiddenList.RemoveAt(idx)
        HiddenList.Push(hwnd)
    }
}

SameSideOrAltTab() {
    active := WinGetID("A")
    if !active
        return

    ; 工作区与中线（这里取主屏；如想取活动窗所在屏，可自行扩展）
    MonitorGetWorkArea(1, &L, &T, &R, &B)
    midX := (L + R) // 2

    WinGetPos &ax, , &aw, , active
    curRight := (ax + aw // 2) >= midX

    winList := WinGetList()
    sameSide := []
    for hwnd in winList {
        if (hwnd = active)
            continue
        if WinGetMinMax(hwnd) = -1
            continue
        if (WinGetExStyle(hwnd) & 0x80)  ; WS_EX_TOOLWINDOW
            continue
        WinGetPos &x, , &w, &h, hwnd
        if (w < (R - L) * MIN_RATIO || h < (B - T) * MIN_RATIO)
            continue
        center := x + w // 2
        thisRight := center >= midX
        if (thisRight = curRight)
            sameSide.Push(hwnd)
    }

    if (sameSide.Length) {
        WinActivate sameSide[1]    ; Z-order 已按顶→底
    } else {
        Send("{Alt down}{Tab}{Alt up}")  ; 退化为系统 Alt-Tab
    }
}

; ---------- 更新 HiddenList ----------
UpdateHiddenList() {
    HiddenList := []  ; 清空

    MonitorGetWorkArea(1, &L, &T, &R, &B)
    workW := R - L, workH := B - T

    winList := WinGetList()   ; 顶→底
    covered := []             ; 已覆盖矩形列表

    for hwnd in winList {
        if WinGetMinMax(hwnd) = -1
            continue
        if (WinGetExStyle(hwnd) & 0x80)  ; WS_EX_TOOLWINDOW
            continue
        WinGetPos &x, &y, &w, &h, hwnd
        if (w < workW * MIN_RATIO || h < workH * MIN_RATIO)
            continue

        rect := { L: x, T: y, R: x + w, B: y + h }
        totalArea := w * h
        hiddenArea := 0
        for c in covered
            hiddenArea += Area(Intersect(rect, c))

        if (hiddenArea / totalArea >= COVER_THRESHOLD) {
            HiddenList.Push(hwnd)
        } else {
            covered.Push(rect)
        }
    }
}

; ---------- 工具函数 ----------
ArrIndexOf(arr, val) {
    for i, v in arr
        if (v = val)
            return i
    return 0
}
Area(r) => (r ? Max(0, r.R - r.L) * Max(0, r.B - r.T) : 0)
Intersect(a, b) {
    L := Max(a.L, b.L), R := Min(a.R, b.R)
    T := Max(a.T, b.T), B := Min(a.B, b.T)
    return (R > L && B > T) ? { L: L, T: T, R: R, B: B } : 0
}
