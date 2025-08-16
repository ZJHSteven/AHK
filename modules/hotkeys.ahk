; ============================================
; 你的热键集合（保持与你原脚本的功能一致）
; ============================================

; Ctrl + Alt + Space → 媒体播放/暂停
^!Space:: {
    Send("{Media_Play_Pause}")
}

; Ctrl + Alt + C → 去换行复制（先复制，再把 CR/LF 都去掉）
^!c:: {
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
