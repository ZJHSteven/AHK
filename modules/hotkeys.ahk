#Include utils.ahk
#Include sandbox_bridge.ahk
#Include spotify_controls.ahk
#Include ctrlx_spotify_combo.ahk
#Include chat_message_cleaner.ahk
; ============================================
; 你的热键集合（保持与你原脚本的功能一致）
; ============================================
; 自提权
if !A_IsAdmin {
    Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

; ============================================
; Ctrl+X 分流为两键/三键（保留剪切 + 扩展 Ctrl+X+Space）
; 具体状态机细节已经抽到 ctrlx_spotify_combo.ahk，
; 这里的职责只保留“热键入口”，避免热键文件继续膨胀。
; ============================================

; Ctrl+X 按下：开始一笔短暂的“待判定事务”
; - 若后续很快跟上 Space，则走 Spotify 分支。
; - 若没有跟上 Space，则在模块内部自动回落为普通剪切。
$^x:: {
    CtrlXComboBegin()
}

; X 抬起：这里只更新“X 已抬起”的状态，不再在这里补发剪切。
; 真正的剪切时机统一由模块内的短时计时器决定。
#HotIf g_CtrlX_Pending
$*x up:: {
    CtrlXComboMarkXUp()
}
#HotIf

; 仅在 Ctrl+X 事务中且 X 仍按住时：左 Ctrl + Space 触发 Spotify（吞掉空格，不回车）
#HotIf g_CtrlX_Pending && g_CtrlX_XDown
<^Space:: {
    CtrlXComboConsumeAsSpotify()
}
#HotIf

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

; Ctrl + Win + C -> 聊天消息清洗复制
; 说明：
; 1) 先执行 Ctrl+C 获取聊天原文。
; 2) 自动去掉时间戳，并把多行消息压平成单行。
; 3) 输出格式固定为“昵称: 内容”，每条消息一行。
; 4) 昵称映射读取 config/chat_name_alias.toml，修改后无需 Reload。
^#c:: {
    ChatCopyNormalizeMessages()        ; 具体解析逻辑放在独立模块，热键入口保持简短
}

; 鼠标前进键 → 复制
XButton2:: {
    Send("^c")
}

; 鼠标后退键 → 粘贴
XButton1:: {
    Send("^v")
}

; Ctrl + Alt + C -> 沙盒中转复制（支持：单文件、多文件、文件夹）
; 说明：
; 1) 先在资源管理器中选中要发送的项目。
; 2) 按下该热键后，会复制到微信/QQ沙盒下载目录下的 __AHK_Transit__ 子目录。
; 3) 若存在上一次任务残留，会先自动清理再开始新任务。
^!c:: {
    SandboxBridgeStageFromSelection()  ; 具体复制与状态机逻辑在 sandbox_bridge.ahk 中
}

; Ctrl + Alt + V -> 单文件粘贴 / 多文件二次触发清理
; 说明：
; 1) 单文件模式：在微信或QQ聊天窗口按下，会自动粘贴该文件，并在约90秒后自动清理。
; 2) 多文件模式：你先手动发送；发送完成后在2.5秒内再次按下本热键触发清理。
^!v:: {
    SandboxBridgePasteOrCleanup()      ; 统一入口：内部会自动判断当前模式与窗口类型
}

; Left Ctrl + Space → 回车（<^ 表示只用左 Ctrl）
#HotIf !(g_CtrlX_Pending && g_CtrlX_XDown)
<^Space:: {
    Send("{Enter}")
}
#HotIf
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
