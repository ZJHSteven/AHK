#Requires AutoHotkey v2.0
; ============================================
; 沙盒中转模块测试
; --------------------------------------------
; 这组测试优先覆盖“本次修复真正依赖的纯逻辑”：
; 1) Explorer 窗口匹配。
; 2) 路径去重与缺失路径过滤。
; 3) 从 Shell 窗口集合中解析选中项。
;
; 说明：
; - 这里不强行驱动真实 Explorer UI 做自动化选择，因为那会把测试变成高度依赖桌面现场的集成测试。
; - 但我们把核心逻辑抽成可注入的函数后，至少能稳定验证当前修复不会在重构时退化。
; ============================================

#Include ..\modules\utils.ahk
#Include ..\modules\sandbox_bridge.ahk

global g_TestPassCount := 0

try {
    SandboxBridgeRunAllTests()
    FileAppend("OK: " g_TestPassCount " tests passed.`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " err.Message "`n", "*", "UTF-8")
    ExitApp(1)
}

SandboxBridgeRunAllTests() {
    SandboxBridgeTestShellWindowHwndMatches()
    SandboxBridgeTestCollectExistingPathDedupsAndFilters()
    SandboxBridgeTestResolveShellWindowSelectionFindsMatchingExplorer()
    SandboxBridgeTestResolveShellWindowSelectionReturnsEmptyWhenNoMatch()
}

SandboxBridgeAssertTrue(value, caseName) {
    global g_TestPassCount
    if !value {
        throw Error(caseName " 断言失败：结果应为 true。")
    }
    g_TestPassCount += 1
}

SandboxBridgeAssertEqual(actual, expected, caseName) {
    global g_TestPassCount
    if (actual != expected) {
        throw Error(caseName " 断言失败。期望：" expected "，实际：" actual)
    }
    g_TestPassCount += 1
}

SandboxBridgeTestShellWindowHwndMatches() {
    SandboxBridgeAssertTrue(SandboxBridgeShellWindowHwndMatches("123456", 123456), "字符串 hwnd 与整数 hwnd 应视为同一窗口")
    SandboxBridgeAssertTrue(!SandboxBridgeShellWindowHwndMatches(123456, 654321), "不同 hwnd 不应误匹配")
}

SandboxBridgeTestCollectExistingPathDedupsAndFilters() {
    root := A_Temp "\ahk_sandbox_bridge_collect_" A_TickCount
    filePath := root "\sample.txt"
    dirPath := root "\sample_dir"
    selected := []
    dedup := Map()

    try {
        DirCreate(root)
        DirCreate(dirPath)
        FileAppend("demo", filePath, "UTF-8")

        SandboxBridgeCollectExistingPath(selected, dedup, filePath, "test file")
        SandboxBridgeCollectExistingPath(selected, dedup, filePath, "test duplicate")
        SandboxBridgeCollectExistingPath(selected, dedup, dirPath, "test dir")
        SandboxBridgeCollectExistingPath(selected, dedup, root "\missing.txt", "test missing")
        SandboxBridgeCollectExistingPath(selected, dedup, "   ", "test blank")

        SandboxBridgeAssertEqual(selected.Length, 2, "应只采纳真实存在且不重复的文件与目录")
        SandboxBridgeAssertEqual(selected[1], filePath, "第一项应为真实文件路径")
        SandboxBridgeAssertEqual(selected[2], dirPath, "第二项应为真实目录路径")
    } finally {
        if DirExist(root) {
            try DirDelete(root, true)
        }
    }
}

SandboxBridgeTestResolveShellWindowSelectionFindsMatchingExplorer() {
    root := A_Temp "\ahk_sandbox_bridge_shell_" A_TickCount
    filePath := root "\picked.txt"
    dirPath := root "\picked_dir"

    try {
        DirCreate(root)
        DirCreate(dirPath)
        FileAppend("demo", filePath, "UTF-8")

        shellWindows := [
            SandboxBridgeFakeShellWindow(1001, []),
            SandboxBridgeFakeShellWindow(2002, [
                SandboxBridgeFakeFolderItem(filePath),
                SandboxBridgeFakeFolderItem(filePath),  ; 故意重复，验证去重
                SandboxBridgeFakeFolderItem(dirPath)
            ])
        ]

        selected := SandboxBridgeResolveShellWindowSelection(shellWindows, 2002)
        SandboxBridgeAssertEqual(selected.Length, 2, "匹配窗口的选中项应被正确解析并去重")
        SandboxBridgeAssertEqual(selected[1], filePath, "匹配窗口的第一项应为文件")
        SandboxBridgeAssertEqual(selected[2], dirPath, "匹配窗口的第二项应为目录")
    } finally {
        if DirExist(root) {
            try DirDelete(root, true)
        }
    }
}

SandboxBridgeTestResolveShellWindowSelectionReturnsEmptyWhenNoMatch() {
    shellWindows := [
        SandboxBridgeFakeShellWindow(3003, [SandboxBridgeFakeFolderItem("C:\definitely-missing-path.txt")])
    ]
    selected := SandboxBridgeResolveShellWindowSelection(shellWindows, 9999)
    SandboxBridgeAssertEqual(selected.Length, 0, "没有匹配窗口时应稳定返回空数组")
}

SandboxBridgeFakeShellWindow(hwnd, items) {
    return {
        HWND: hwnd,
        Document: SandboxBridgeFakeDocument(items)
    }
}

SandboxBridgeFakeDocument(items) {
    doc := {}
    doc.DefineProp("SelectedItems", {
        Call: (*) => items
    })
    return doc
}

SandboxBridgeFakeFolderItem(path) {
    return {
        Path: path
    }
}
