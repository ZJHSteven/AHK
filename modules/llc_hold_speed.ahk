#Requires AutoHotkey v2.0

; ======= 配置区 =======

boostKey := "F"   ; 按住这个键临时加速
boostTimes := 3     ; 按下时发送多少次 L（你可以自己试着调）
resetTimes := 3     ; 松开时发送多少次 J（一般和上面保持一致）

; ======= 变量 =======

global g_boostOn := false  ; 标记“现在是否处在加速状态”

IsLosslessCutActive() {
    activeTitle := WinGetTitle("A")  ; A = 当前前台窗口
    return InStr(activeTitle, "LosslessCut")
}

; ======= 按下 F：开始加速 =======

$F::
{
    global g_boostOn, boostTimes

    if !IsLosslessCutActive()
        return

    ; --- 防止键盘长按自动重复把热键触发多次 ---
    ; 如果上一次也是 F 并且时间间隔很短，就直接忽略
    if (A_PriorHotkey = "F" && A_TimeSincePriorHotkey < 300)
        return

    ; 已经在加速状态就别再叠加了
    if g_boostOn
        return
    g_boostOn := true

    ; 这里默认你当前是 1.0x，用 L 把速度提上去
    loop boostTimes {
        SendEvent "l"
        Sleep 30
    }
}

; ======= 松开 F：恢复正常 =======

$F up::
{
    global g_boostOn, resetTimes

    if !IsLosslessCutActive()
        return

    if !g_boostOn
        return
    g_boostOn := false

    ; 用同样次数的 J，把速度尽量拉回原来的级别
    loop resetTimes {
        SendEvent "j"
        Sleep 30
    }
}
