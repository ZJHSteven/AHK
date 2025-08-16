; ============================================
; 通用工具 / 提示
; ============================================

; Toast(msg, ms)
; - 在 Win10/11 上，系统通知停留时长由系统控制，ms 仅用于辅助的 ToolTip。
; - 如果你只想系统通知，不要 ToolTip，把 ToolTip 两行注释掉即可。
Toast(msg, ms := 1200) {
    try TrayTip("AutoHotkey", msg)     ; 系统通知（停留时长由系统控制）
    ToolTip(msg)                        ; 屏幕小气泡
    SetTimer(() => ToolTip(), -ms)      ; ms 毫秒后关掉小气泡
}
