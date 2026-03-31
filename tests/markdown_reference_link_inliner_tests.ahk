#Requires AutoHotkey v2.0
; ============================================
; Markdown 引用式链接展开模块测试
; --------------------------------------------
; 这个测试脚本只验证“纯文本转换逻辑”，不依赖真实热键与真实剪贴板交互。
; 这样可以：
; 1) 快速覆盖正常场景、边界场景和异常输入。
; 2) 避免热键文件中的提权逻辑干扰测试自动化。
; 3) 出现失败时直接定位到具体用例。
; ============================================

#Include ..\modules\markdown_reference_link_inliner.ahk

global g_TestPassCount := 0                                             ; 统计通过用例数，便于输出总览

try {
    MarkdownRunAllInlineLinkTests()                                     ; 执行全部测试用例
    FileAppend("OK: " g_TestPassCount " tests passed.`n", "*", "UTF-8") ; 成功时向标准输出打印摘要
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " err.Message "`n", "*", "UTF-8")                 ; 失败时打印错误，供终端直接查看
    ExitApp(1)
}

; 测试总入口：按“核心能力 -> 兼容场景 -> 边界异常”组织
MarkdownRunAllInlineLinkTests() {
    MarkdownTestStandardReferenceLink()                                 ; 标准 `[文本][1]` 替换
    MarkdownTestCollapsedReferenceLink()                                ; 折叠写法 `[文本][]`
    MarkdownTestShortcutReferenceLink()                                 ; 快捷写法 `[1]`
    MarkdownTestCaseInsensitiveLabelMatch()                             ; 标签大小写不敏感
    MarkdownTestTitleWithInnerQuotes()                                  ; 宽松兼容标题中的裸双引号
    MarkdownTestImageReferenceLink()                                    ; 图片引用也能展开
    MarkdownTestUnresolvedReferenceKeepsOriginal()                      ; 未命中定义时保持原文
    MarkdownTestDefinitionsOnlyDoNotMutateText()                        ; 只有定义、没有正文引用时不修改
    MarkdownTestInvalidDefinitionIsIgnored()                            ; 非法定义不应误判
    MarkdownTestMultipleReferencesShareSameDefinition()                 ; 同一标签可被多次复用
}

; 工具：断言两个字符串完全一致
MarkdownAssertEqual(actual, expected, caseName) {
    global g_TestPassCount
    if (actual != expected) {
        throw Error(caseName " 断言失败。`n期望：`n" expected "`n实际：`n" actual)
    }
    g_TestPassCount += 1                                                ; 断言成功就累计一次通过
}

; 工具：断言条件为真
MarkdownAssertTrue(value, caseName) {
    global g_TestPassCount
    if !value {
        throw Error(caseName " 断言失败：结果应为 true。")
    }
    g_TestPassCount += 1                                                ; 成功时增加通过计数
}

; 工具：断言条件为假
MarkdownAssertFalse(value, caseName) {
    global g_TestPassCount
    if value {
        throw Error(caseName " 断言失败：结果应为 false。")
    }
    g_TestPassCount += 1                                                ; 成功时增加通过计数
}

; 标准显式引用：`[Zenodo][1]` -> `[Zenodo](<url> "title")`
MarkdownTestStandardReferenceLink() {
    input := "出处见 [Zenodo][1]。`n`n[1]: https://zenodo.org/records/14287127 ""Zenodo"""
    result := MarkdownInlineReferenceLinks(input)                       ; 执行纯函数转换
    expected := "出处见 [Zenodo](<https://zenodo.org/records/14287127> ""Zenodo"")。"

    MarkdownAssertTrue(result["changed"], "标准显式引用-变更标记")      ; 应该识别到有效改写
    MarkdownAssertEqual(result["text"], expected, "标准显式引用-输出文本")
    MarkdownAssertEqual(result["replacementCount"], 1, "标准显式引用-替换计数")
}

; 折叠引用：`[Zenodo][]` 的标签等于显示文本本身
MarkdownTestCollapsedReferenceLink() {
    input := "来源：[Zenodo][]`n[zenodo]: https://zenodo.org/records/1"
    result := MarkdownInlineReferenceLinks(input)
    expected := "来源：[Zenodo](<https://zenodo.org/records/1>)"

    MarkdownAssertTrue(result["changed"], "折叠引用-变更标记")
    MarkdownAssertEqual(result["text"], expected, "折叠引用-输出文本")
}

; 快捷引用：`[1]` 直接使用自身作为标签
MarkdownTestShortcutReferenceLink() {
    input := "详细信息见[1]。`n[1]: https://example.com/ref"
    result := MarkdownInlineReferenceLinks(input)
    expected := "详细信息见[1](<https://example.com/ref>)。"

    MarkdownAssertTrue(result["changed"], "快捷引用-变更标记")
    MarkdownAssertEqual(result["text"], expected, "快捷引用-输出文本")
}

; 标签匹配应忽略大小写与多余空白
MarkdownTestCaseInsensitiveLabelMatch() {
    input := "链接：[Zenodo][A   B]。`n[a b]: https://example.com/case"
    result := MarkdownInlineReferenceLinks(input)
    expected := "链接：[Zenodo](<https://example.com/case>)。"

    MarkdownAssertTrue(result["changed"], "大小写与空白归一-变更标记")
    MarkdownAssertEqual(result["text"], expected, "大小写与空白归一-输出文本")
}

; AI 常见问题：标题里夹了裸双引号，也应尽量保留下来并转义成可迁移的行内标题
MarkdownTestTitleWithInnerQuotes() {
    rawTitle := "临床医学五年制第十轮 " Chr(34) "十四五" Chr(34) " 规划教材"
    input := "[Zenodo][1]`n[1]: https://zenodo.org/records/14287127 " Chr(34) rawTitle Chr(34)
    result := MarkdownInlineReferenceLinks(input)
    expected := "[Zenodo](<https://zenodo.org/records/14287127> ""临床医学五年制第十轮 \""十四五\"" 规划教材"")"

    MarkdownAssertTrue(result["changed"], "裸双引号标题-变更标记")
    MarkdownAssertEqual(result["text"], expected, "裸双引号标题-输出文本")
}

; 图片引用：`![图1][img]` 也应该展开成行内图片链接
MarkdownTestImageReferenceLink() {
    input := "示意图：![图1][img]`n[img]: https://example.com/a.png '封面图'"
    result := MarkdownInlineReferenceLinks(input)
    expected := "示意图：![图1](<https://example.com/a.png> ""封面图"")"

    MarkdownAssertTrue(result["changed"], "图片引用-变更标记")
    MarkdownAssertEqual(result["text"], expected, "图片引用-输出文本")
}

; 正文引用未命中定义时，必须完整保留原文，避免“改坏”
MarkdownTestUnresolvedReferenceKeepsOriginal() {
    input := "这里有 [Zenodo][2]。`n[1]: https://example.com/ok"
    result := MarkdownInlineReferenceLinks(input)

    MarkdownAssertFalse(result["changed"], "未命中定义-变更标记")
    MarkdownAssertEqual(result["text"], input, "未命中定义-输出文本")
    MarkdownAssertEqual(result["replacementCount"], 0, "未命中定义-替换计数")
}

; 只有定义、没有正文引用时，不应擅自删掉定义区
MarkdownTestDefinitionsOnlyDoNotMutateText() {
    input := "[1]: https://example.com/only-definition"
    result := MarkdownInlineReferenceLinks(input)

    MarkdownAssertFalse(result["changed"], "只有定义-变更标记")
    MarkdownAssertEqual(result["text"], input, "只有定义-输出文本")
}

; 非法定义格式要被忽略，避免误把普通文本删掉
MarkdownTestInvalidDefinitionIsIgnored() {
    input := "普通文本`n[1] https://example.com/not-a-definition"
    result := MarkdownInlineReferenceLinks(input)

    MarkdownAssertFalse(result["changed"], "非法定义-变更标记")
    MarkdownAssertEqual(result["definitionCount"], 0, "非法定义-定义计数")
}

; 同一个标签在正文中多次出现时，应该全部替换
MarkdownTestMultipleReferencesShareSameDefinition() {
    input := "[Zenodo][1] 和 [再次查看][1]。`n[1]: https://zenodo.org/records/42 ""资料页"""
    result := MarkdownInlineReferenceLinks(input)
    expected := "[Zenodo](<https://zenodo.org/records/42> ""资料页"") 和 [再次查看](<https://zenodo.org/records/42> ""资料页"")。"

    MarkdownAssertTrue(result["changed"], "重复引用-变更标记")
    MarkdownAssertEqual(result["text"], expected, "重复引用-输出文本")
    MarkdownAssertEqual(result["replacementCount"], 2, "重复引用-替换计数")
}
