; ============================================
; 简化版：监听 3 个 Sandboxie 下载夹
; 每100毫秒扫描一次，发现文件立即移动
; ============================================

; 监听的三个沙盒下载夹
global SBX_SOURCES := [
    "D:\Sandboxie\WeChat\user\current\Downloads",
    "D:\Sandboxie\Tencent_Meeting\user\current\Downloads",
    "D:\Sandboxie\QQ\user\current\Downloads"
]

; 目标目录
global DST := "C:\Users\ZJHSteven\Downloads"

; 开始监听
StartSandboxWatch() {
    ; 确保目标目录存在
    if !DirExist(DST) {
        try DirCreate(DST)
    }

    ; 每100毫秒扫描一次
    SetTimer(ScanAndMove, 100)
}

; 扫描并移动文件
ScanAndMove() {
    for _, src in SBX_SOURCES {
        ; 跳过不存在的目录
        if !DirExist(src)
            continue

        ; 扫描目录中的所有文件
        loop files, src "\*.*", "F" {
            ; 跳过临时文件（正在下载的文件）
            ext := StrLower(A_LoopFileExt)
            if (ext = "crdownload" || ext = "part" || ext = "tmp" || ext = "download")
                continue

            ; 立即移动文件
            try {
                FileMove(A_LoopFileFullPath, DST "\" A_LoopFileName, 1)
                ToolTip("已移动: " . A_LoopFileName, 100, 100)
                SetTimer(() => ToolTip(), -1000)  ; 1秒后隐藏提示
            } catch {
                ; 移动失败，可能文件被占用，下次再试
            }
        }
    }
}
