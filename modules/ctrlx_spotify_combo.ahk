; ============================================
; Ctrl+X / Ctrl+X+Space 组合键状态机模块
; --------------------------------------------
; 这个模块专门负责处理“普通 Ctrl+X 剪切”和“Ctrl+X+Space 唤起 Spotify”之间的分流。
;
; 为什么要单独拆出来：
; 1) 原实现是在 `x up`（也就是 X 抬起）时再补发一次 `^x`。
; 2) 这种“抬起后再补发”的做法，在中文输入法（IME）的组合态里不够稳定，
;    有机会被系统或输入法误解释成普通字符输入，表现为没有剪切，反而打出一个 `x`。
; 3) 新实现改成“开启一个很短的判定窗口”：
;    - 如果窗口期内按下 Space，就认定为 Ctrl+X+Space，执行 Spotify 动作。
;    - 如果窗口期结束还没按 Space，就统一补发一次真正的剪切。
;
; 这样做的取舍：
; - 优点：避免把“是否剪切”的决定绑死在 `x up` 这个时刻，输入法兼容性更稳。
; - 代价：普通 Ctrl+X 会比原生剪切多一个很短的等待窗口（默认约 180ms）。
; ============================================

global g_CtrlX_Pending := false                        ; 是否存在一笔“尚未最终决定用途”的 Ctrl+X 事务
global g_CtrlX_Consumed := false                       ; 这笔事务是否已经被 Ctrl+X+Space 消费
global g_CtrlX_XDown := false                          ; 当前是否仍认为 X 物理按键处于按下状态
global g_CtrlX_ComboWindowMs := 180                    ; 判定窗口：给 Space 一个很短的跟进时间
global g_CtrlX_SendCutCallback := CtrlXComboSendNativeCut
global g_CtrlX_ActivateSpotifyCallback := CtrlXComboActivateSpotify

CtrlXComboBegin() {
    global g_CtrlX_Pending, g_CtrlX_Consumed, g_CtrlX_XDown, g_CtrlX_ComboWindowMs

    ; 每次开始新事务前，都先把上一轮遗留计时器停掉，避免旧状态串到新按键里。
    SetTimer(CtrlXComboFinalizePendingCut, 0)

    ; 标记本次 Ctrl+X 已经开始，但暂时还不立刻决定它到底是“剪切”还是“Spotify 组合键”。
    g_CtrlX_Pending := true
    g_CtrlX_Consumed := false
    g_CtrlX_XDown := true

    ; 开一个一次性计时器：
    ; 如果在这段窗口时间内没有被 Space 消费，就自动回落为普通 Ctrl+X 剪切。
    SetTimer(CtrlXComboFinalizePendingCut, -g_CtrlX_ComboWindowMs)
}

CtrlXComboMarkXUp() {
    global g_CtrlX_Pending, g_CtrlX_XDown

    ; 这里只负责记录“X 已经抬起”这个事实，不再在这里补发剪切。
    ; 这样可以避免旧实现那种“刚好在抬起瞬间补发 ^x”带来的输入法兼容问题。
    if g_CtrlX_Pending {
        g_CtrlX_XDown := false
    }
}

CtrlXComboConsumeAsSpotify() {
    global g_CtrlX_Pending, g_CtrlX_XDown, g_CtrlX_Consumed, g_CtrlX_ActivateSpotifyCallback

    ; 只有在“事务仍有效”且“X 仍被按住”时，才允许把这次输入解释成 Ctrl+X+Space。
    if !(g_CtrlX_Pending && g_CtrlX_XDown) {
        return false
    }

    ; 一旦被 Space 消费，就立刻取消后续的剪切回落，避免 Spotify 和剪切同时发生。
    g_CtrlX_Consumed := true
    SetTimer(CtrlXComboFinalizePendingCut, 0)

    ; 执行外部动作：默认是唤起 Spotify。
    g_CtrlX_ActivateSpotifyCallback.Call()

    ; 动作做完马上清空状态，避免后续按键被错误继承到这次事务里。
    CtrlXComboResetState()
    return true
}

CtrlXComboFinalizePendingCut() {
    global g_CtrlX_Pending, g_CtrlX_Consumed, g_CtrlX_SendCutCallback

    ; 如果事务早就结束了，说明这是过期计时器回调，直接做幂等清理即可。
    if !g_CtrlX_Pending {
        CtrlXComboResetState()
        return false
    }

    ; 如果已经被 Ctrl+X+Space 消费，也不应该再补发剪切。
    if g_CtrlX_Consumed {
        CtrlXComboResetState()
        return false
    }

    ; 先清状态，再发剪切。
    ; 这样可以确保补发出来的 Ctrl+X 不会再次撞进当前这套状态机里。
    CtrlXComboResetState()
    g_CtrlX_SendCutCallback.Call()
    return true
}

CtrlXComboResetState() {
    global g_CtrlX_Pending, g_CtrlX_Consumed, g_CtrlX_XDown

    ; 无论通过哪条路径结束事务，都统一从这里收口，保证状态清理逻辑只有一份。
    SetTimer(CtrlXComboFinalizePendingCut, 0)
    g_CtrlX_Pending := false
    g_CtrlX_Consumed := false
    g_CtrlX_XDown := false
}

CtrlXComboSendNativeCut() {
    ; 使用显式的按下/抬起事件补发 Ctrl+X，
    ; 比把逻辑绑定在 `x up` 时点上更稳，也更接近真实快捷键序列。
    SendEvent("{Ctrl down}{x down}{x up}{Ctrl up}")
}

CtrlXComboActivateSpotify() {
    ; 把真正的业务动作继续委托给现有 Spotify 控制模块，
    ; 这样本模块只关心“按键状态机”，不关心播放器实现细节。
    ActivateSpotifyToFront()
}
