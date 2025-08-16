; ============================================
; 监听 3 个 Sandboxie 下载夹，一旦发现“下载完成”的新文件，
; 自动搬运到宿主机下载目录。
;
; 设计原则：
;  - 轻量：默认每 1000ms 扫描一次（可调）
;  - 稳定：以“文件大小连续两轮不变”判断完成
;  - 安全：跳过临时后缀（.crdownload/.part/.tmp 等）
; ============================================

; ---- 你要监听的三个沙盒下载夹（按你提供的真实路径） ----
global SBX_SOURCES := [
    "D:\Sandboxie\WeChat\user\current\Downloads",
    "D:\Sandboxie\Tencent_Meeting\user\current\Downloads",
    "D:\Sandboxie\QQ\user\current\Downloads"
]

; ---- 目标：宿主机下载夹 ----
; 默认自动识别 C:\Users\<User>\Downloads，如需用 D:\Downloads，请改成：
;   DST := "D:\Downloads"
global DST := EnvGet("USERPROFILE") "\Downloads"

; ---- 跳过的临时扩展名（未下载完） ----
global SKIP_EXT := Map(
    "crdownload", 1, "download", 1, "part", 1, "partial", 1, "tmp", 1, "tdownload", 1
)

; ---- 记录表：判断“文件是否完成”的状态（跨多目录共用） ----
global SEEN := Map()

; ---- 开始监听（interval 毫秒） ----
StartSandboxWatch(interval := 1000, showToast := true) {
    ; 目标目录存在性
    if !DirExist(DST) {
        try DirCreate(DST)
    }
    ; 每个源目录不存在也不报错，只是跳过
    SetTimer(WatchTick.Bind(showToast), interval)
}

WatchTick(showToast) {
    ; 扫每个源目录
    for _, src in SBX_SOURCES {
        if !DirExist(src)
            continue

        loop files, src "\*.*", "F" {
            path := A_LoopFileFullPath
            ; 忽略隐藏/系统/目录
            if InStr(A_LoopFileAttrib, "D") || InStr(A_LoopFileAttrib, "H") || InStr(A_LoopFileAttrib, "S")
                continue

            ext := StrLower(A_LoopFileExt)
            if SKIP_EXT.Has(ext)
                continue

            size := FileGetSize(path)
            now := A_TickCount
            prev := SEEN.Has(path) ? SEEN[path] : { size: -1, t: 0 }

            ; 大小连续两次稳定（>2个 interval），认为完成
            if (size = prev.size && now - prev.t > 2000) {
                try {
                    ; 确保目标存在
                    if !DirExist(DST)
                        DirCreate(DST)

                    FileMove(path, DST "\" A_LoopFileName, 1)  ; 1=覆盖同名
                    SEEN.Delete(path)
                    if showToast
                        Toast("📥 已移出沙盒 → " . A_LoopFileName, 1200)
                } catch {
                    ; 被占用或业务锁定，留待下一轮
                    SEEN[path] := { size: size, t: now }
                }
            } else {
                SEEN[path] := { size: size, t: now }
            }
        }
    }

    ; 清理已不存在的记录
    for f, _ in SEEN.Clone()
        if !FileExist(f)
            SEEN.Delete(f)
}
