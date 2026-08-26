; ============================================
; AHK 主进程统一运行日志
; ============================================
; 目标：
; - 常驻 AHK 启动、退出和未处理运行时错误都有可追溯记录；
; - 默认写入 D:\Workspace\AHK\logs\runtime\；
; - 日志按日期分文件，并在单日日志过大时做有限大小轮转；
; - 自动删除超过保留天数的旧日志，避免无人值守时无限膨胀。
;
; 注意：
; - 这是主 AHK 的“运行时/守护”日志，不替代各业务模块已有的专项日志。
; - 日志自身必须尽量不抛异常，否则错误处理器可能形成递归。因此所有写盘路径都用 try 包裹。

AhkRuntimeLoggerInitialize() {
    ; 注册在主脚本生命周期最前面：后续模块若抛出未处理错误，也能留下日志。
    OnError(AhkRuntimeHandleUnhandledError)
    OnExit(AhkRuntimeHandleExit)

    AhkRuntimeLog("INFO", "AHK 主进程启动"
        . " | pid=" ProcessExist()
        . " | ahk=" A_AhkVersion
        . " | exe=" A_AhkPath
        . " | admin=" (A_IsAdmin ? "yes" : "no"))
}

AhkRuntimeHandleUnhandledError(err, mode) {
    ; mode=Return 表示错误所在线程可结束；mode=Exit 表示关键错误，脚本仍会退出。
    ; 返回 1 会阻止 AutoHotkey 再弹默认错误 GUI；对于关键错误并不会阻止进程退出。
    message := "未处理运行时错误"
        . " | mode=" mode
        . " | type=" Type(err)
        . " | message=" AhkRuntimeSafeErrorProp(err, "Message")
        . " | what=" AhkRuntimeSafeErrorProp(err, "What")
        . " | extra=" AhkRuntimeSafeErrorProp(err, "Extra")
        . " | file=" AhkRuntimeSafeErrorProp(err, "File")
        . " | line=" AhkRuntimeSafeErrorProp(err, "Line")
        . "`nstack:`n" AhkRuntimeSafeErrorProp(err, "Stack")

    AhkRuntimeLog("ERROR", message)
    return 1
}

AhkRuntimeHandleExit(exitReason, exitCode) {
    ; Reload / #SingleInstance / 关机 / 正常 Exit 都会进入这里，便于区分“崩了”还是“被替换”。
    AhkRuntimeLog("INFO", "AHK 主进程退出 | reason=" exitReason " | code=" exitCode)
}

AhkRuntimeSafeErrorProp(err, propName) {
    ; Error 的不同子类未必所有字段都有有意义的值；统一安全读取，避免日志处理再次抛错。
    try {
        if err.HasProp(propName)
            return String(err.%propName%)
    }
    return ""
}

AhkRuntimeLog(level, message) {
    ; 日志写入绝不能影响热键主流程，因此即使目录/磁盘临时异常也只静默放弃本条日志。
    try {
        logDir := A_ScriptDir "\logs\runtime"
        DirCreate(logDir)

        AhkRuntimeCleanupOldLogs(logDir, 14)

        day := FormatTime(, "yyyy-MM-dd")
        logPath := logDir "\ahk-runtime-" day ".log"
        AhkRuntimeRotateBySize(logPath, 5 * 1024 * 1024, 3)

        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        normalized := StrReplace(String(message), "`r`n", "`n")
        normalized := StrReplace(normalized, "`r", "`n")
        normalized := StrReplace(normalized, "`n", "`r`n    ")
        FileAppend(timestamp " [" level "] " normalized "`r`n", logPath, "UTF-8")
    }
}

AhkRuntimeRotateBySize(logPath, maxBytes, backups) {
    ; 同一天日志超过上限后：.1 为最新备份，最多保留指定份数。
    if !FileExist(logPath)
        return

    try {
        if FileGetSize(logPath) < maxBytes
            return
    } catch {
        return
    }

    try {
        oldest := logPath "." backups
        if FileExist(oldest)
            FileDelete(oldest)

        index := backups - 1
        while index >= 1 {
            source := logPath "." index
            target := logPath "." (index + 1)
            if FileExist(source)
                FileMove(source, target, 1)
            index -= 1
        }

        FileMove(logPath, logPath ".1", 1)
    }
}

AhkRuntimeCleanupOldLogs(logDir, retentionDays) {
    ; 一天内可能调用很多次日志函数，所以这里用静态变量限制为每小时最多清理一次。
    static lastCleanupTick := 0
    if lastCleanupTick != 0 && (A_TickCount - lastCleanupTick) < 60 * 60 * 1000
        return
    lastCleanupTick := A_TickCount

    cutoff := DateAdd(A_Now, -retentionDays, "Days")
    Loop Files, logDir "\ahk-runtime-*.log*", "F" {
        try {
            if A_LoopFileTimeModified < cutoff
                FileDelete(A_LoopFileFullPath)
        }
    }
}
