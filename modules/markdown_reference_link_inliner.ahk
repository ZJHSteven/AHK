; ============================================
; Markdown 引用式链接展开模块
; --------------------------------------------
; 这个模块专门解决一类很常见、但复制迁移时特别容易“丢链接”的 Markdown 文本：
; 1) 正文里写的是 `[文本][1]`、`[文本][]`、`[1]` 这类“引用式链接”。
; 2) 文末再单独放 `[1]: https://example.com "标题"` 这样的定义表。
; 3) 一旦正文被单独复制走、或者定义表漏带，正文里的链接就全部失效。
;
; 本模块的职责：
; - 从剪贴板读取 Markdown 文本。
; - 解析文中的引用定义表。
; - 把正文里的引用式链接改写成“行内链接”。
; - 成功后写回剪贴板，并移除已经被消费掉的定义行。
;
; 设计取舍说明：
; - 热键层只负责调用入口，具体解析逻辑全部留在本模块，便于后续继续扩展。
; - 为了兼容 AI 常见的“不完全标准 Markdown”，这里对标题解析采取“宽松模式”：
;   例如标题中即使直接出现了裸双引号，也尽量保留并正确转义到行内链接里。
; - 解析重点覆盖你当前最常见的三种引用写法：
;   1) `[文本][标签]`
;   2) `[文本][]`
;   3) `[标签]`（快捷引用）
; ============================================

; 对外入口：把剪贴板中的 Markdown 引用式链接展开为行内链接
; 入参：无（直接读取当前剪贴板文本）
; 返回：true=成功展开并写回剪贴板，false=未处理或处理失败
MarkdownClipboardInlineReferenceLinks() {
    clipBackup := ClipboardAll()                                      ; 先完整备份剪贴板，失败时可无损恢复
    handled := false                                                  ; 记录本次是否真正成功写回，供 finally 判定是否恢复

    try {
        rawText := A_Clipboard                                         ; 读取当前剪贴板中的纯文本内容
        if (Trim(rawText, " `t`r`n") = "") {                          ; 空剪贴板或非文本内容时直接提示
            Toast("⚠️ 剪贴板里没有可处理的文本")
            return false
        }

        result := MarkdownInlineReferenceLinks(rawText)                ; 走纯文本转换主流程，便于测试与复用
        if !result["changed"] {                                       ; 没有任何改写时保留原剪贴板内容
            if (result["definitionCount"] = 0) {
                Toast("⚠️ 未检测到 Markdown 引用式链接定义")
            } else {
                Toast("⚠️ 检测到引用定义，但正文里没有可展开的引用")
            }
            return false
        }

        A_Clipboard := result["text"]                                  ; 把展开后的文本写回剪贴板
        handled := true                                                ; 标记成功，finally 不再回滚
        Toast("✅ 已展开 " result["replacementCount"] " 处 Markdown 引用链接")
        return true
    } catch as err {
        Toast("❌ 链接展开失败：" err.Message)                          ; 出错时给出核心报错信息，便于排查
        return false
    } finally {
        if !handled {                                                  ; 仅在失败/未处理时恢复原剪贴板
            A_Clipboard := clipBackup
        }
        clipBackup := ""                                               ; 显式释放 ClipboardAll 占用的内存
    }
}

; 纯函数：把输入文本中的引用式链接改写为行内链接
; 入参：
; - rawText: 原始 Markdown 文本
; 返回：
; - Map，包含：
;   - changed: 是否有实际改写
;   - text: 改写后的文本（若未改写则保持原文）
;   - definitionCount: 识别出的引用定义数量
;   - replacementCount: 实际替换的引用数量
MarkdownInlineReferenceLinks(rawText) {
    definitions := MarkdownParseReferenceDefinitions(rawText)          ; 先整体扫描，拿到所有引用定义
    result := Map(                                                     ; 先构造默认返回值：未改写时直接复用
        "changed", false,
        "text", rawText,
        "definitionCount", definitions["definitionCount"],
        "replacementCount", 0
    )

    if (definitions["definitionCount"] = 0) {                        ; 没有定义表，说明不是目标格式
        return result
    }

    normalizedText := StrReplace(rawText, "`r", "")                   ; 统一换行符，便于逐行处理
    rawLines := StrSplit(normalizedText, "`n")                        ; 逐行扫描正文与定义区
    outputLines := []                                                  ; 收集改写后的正文行
    replacementCount := 0                                              ; 统计实际替换了多少处引用

    for lineIndex, line in rawLines {                                  ; 定义行和正文行分别处理
        if definitions["definitionLineMap"].Has(lineIndex) {          ; 定义行在成功改写时会被整体移除
            continue
        }

        lineReplacementCount := 0                                      ; 统计当前这一行替换了多少次
        expandedLine := MarkdownExpandReferenceLinksInLine(
            line,
            definitions["entryMap"],
            &lineReplacementCount
        )

        replacementCount += lineReplacementCount                       ; 汇总全局替换次数
        outputLines.Push(expandedLine)                                 ; 无论是否替换，都保留正文原有结构
    }

    if (replacementCount = 0) {                                        ; 有定义但正文没引用到时，不改写原文
        return result
    }

    outputText := MarkdownJoinArray(outputLines, "`n")                 ; 重新拼回文本主体
    outputText := RTrim(outputText, "`n")                              ; 去掉定义区删除后残留的尾部空换行

    result["changed"] := true                                          ; 只要有替换，就认定本次成功改写
    result["text"] := outputText                                       ; 回写改写后的正文
    result["replacementCount"] := replacementCount                     ; 回写统计信息，供提示与测试使用
    return result
}

; 扫描全文中的 Markdown 引用定义
; 支持形态示例：
; - [1]: https://example.com
; - [Zenodo]: <https://example.com> "标题"
; - [A B]: https://example.com '标题'
; 返回：
; - Map("entryMap" => 标签映射表, "definitionLineMap" => 定义行号集合, "definitionCount" => 定义行数量)
MarkdownParseReferenceDefinitions(rawText) {
    entryMap := Map()                                                  ; 标签 -> { url, title } 的映射表
    definitionLineMap := Map()                                         ; 用于后续把定义行从正文中删除
    definitionCount := 0                                               ; 统计识别出了多少条定义行
    normalizedText := StrReplace(rawText, "`r", "")                   ; 统一成 LF，便于行号稳定
    rawLines := StrSplit(normalizedText, "`n")                        ; 逐行检查是否为定义行

    for lineIndex, line in rawLines {                                  ; 只按单行定义处理，贴合当前场景
        normalizedLabel := ""                                          ; 输出参数：标准化后的引用标签
        entry := 0                                                     ; 输出参数：定义详情
        if !MarkdownTryParseReferenceDefinition(line, &normalizedLabel, &entry) {
            continue
        }

        entryMap[normalizedLabel] := entry                             ; 后定义覆盖前定义，贴近 Markdown 常见行为
        definitionLineMap[lineIndex] := true                           ; 记录该行是定义行，后续成功时移除
        definitionCount += 1                                           ; 统计定义总数（按行计）
    }

    return Map(                                                        ; 打包返回，便于主流程统一消费
        "entryMap", entryMap,
        "definitionLineMap", definitionLineMap,
        "definitionCount", definitionCount
    )
}

; 尝试把单行文本解析为 Markdown 引用定义
; 入参：
; - line: 单行原文
; 输出：
; - &normalizedLabel: 标准化后的标签（大小写不敏感、内部空白折叠）
; - &entry: Map("url", url, "title", title)
; 返回：
; - true=解析成功，false=不是有效定义行
MarkdownTryParseReferenceDefinition(line, &normalizedLabel, &entry) {
    normalizedLabel := ""                                              ; 先清空输出参数，避免沿用旧值
    entry := 0                                                         ; 先清空定义详情输出
    if RegExMatch(line, "^\s{4,}") {                                 ; 4 空格以上通常表示代码块，避免误判
        return false
    }

    trimmedLeft := LTrim(line, " `t")                                  ; Markdown 允许最多 3 个前导空白
    if (SubStr(trimmedLeft, 1, 1) != "[") {                           ; 定义必须以 [label]: 开头
        return false
    }

    closeBracketPos := MarkdownFindClosingBracket(trimmedLeft, 1)      ; 找到标签末尾的 ] 位置
    if !closeBracketPos {                                               ; 找不到闭合 ] 说明不是合法定义
        return false
    }
    if (SubStr(trimmedLeft, closeBracketPos + 1, 1) != ":") {         ; ] 后面必须立刻跟冒号
        return false
    }

    rawLabel := SubStr(trimmedLeft, 2, closeBracketPos - 2)            ; 取出定义中的原始标签文本
    remainder := LTrim(SubStr(trimmedLeft, closeBracketPos + 2), " `t") ; 冒号后就是 URL 与可选标题
    if (Trim(rawLabel, " `t") = "" || remainder = "") {               ; 空标签或空 URL 都视为无效定义
        return false
    }

    url := ""                                                          ; 输出参数：解析出的 URL
    title := ""                                                        ; 输出参数：解析出的标题（可空）
    if !MarkdownParseReferenceTarget(remainder, &url, &title) {
        return false                                                   ; URL / 标题解析失败则整行忽略
    }

    normalizedLabel := MarkdownNormalizeReferenceLabel(rawLabel)       ; 统一大小写与空白，便于引用命中
    if (normalizedLabel = "") {                                        ; 防御性检查：标准化后为空则忽略
        return false
    }

    entry := Map("url", url, "title", title)                           ; 组装定义详情对象
    return true
}

; 解析引用定义右侧的 URL 与可选标题
; 说明：
; - URL 支持普通裸 URL 与 `<url>` 两种形态。
; - 标题支持 `"标题"`、`'标题'`、`(标题)` 三种常见写法。
; - 为兼容 AI 常见的“标题里混入未转义双引号”，这里采用宽松解析：
;   只要首尾包裹符完整，就保留中间全部内容。
MarkdownParseReferenceTarget(remainder, &url, &title) {
    url := ""                                                          ; 先清空输出参数
    title := ""                                                        ; 先清空输出参数
    text := Trim(remainder, " `t")                                     ; 去掉右侧整体首尾空白
    if (text = "") {                                                   ; 空字符串无法构成有效目标
        return false
    }

    firstChar := SubStr(text, 1, 1)                                    ; 用首字符判断 URL 是否使用 <...>
    if (firstChar = "<") {
        endPos := InStr(text, ">")                                     ; `<url>` 模式以第一个 > 结束
        if (endPos <= 1) {                                             ; 没有闭合 > 则视为无效
            return false
        }
        url := SubStr(text, 2, endPos - 2)                             ; 取出尖括号内部的 URL
        text := Trim(SubStr(text, endPos + 1), " `t")                  ; 剩余部分继续尝试解析标题
    } else {
        if !RegExMatch(text, "^\S+", &m) {                            ; 裸 URL 读取到第一个空白为止
            return false
        }
        url := m[0]                                                    ; 正则整体匹配就是 URL 本体
        text := Trim(SubStr(text, StrLen(url) + 1), " `t")            ; 剩余部分作为标题候选
    }

    if (url = "") {                                                    ; URL 不能为空
        return false
    }
    if (text = "") {                                                   ; 没有标题时也算合法定义
        return true
    }

    openChar := SubStr(text, 1, 1)                                     ; 根据标题包裹符决定闭合字符
    closeChar := ""
    if (openChar = Chr(34)) {                                          ; 双引号标题：`"title"`
        closeChar := Chr(34)
    } else if (openChar = "'") {                                       ; 单引号标题：`'title'`
        closeChar := "'"
    } else if (openChar = "(") {                                       ; 圆括号标题：`(title)`
        closeChar := ")"
    } else {
        return false                                                   ; 非常见标题格式直接忽略，避免误判
    }

    if (SubStr(text, -1) != closeChar) {                               ; 首尾不成对说明格式不完整
        return false
    }

    title := SubStr(text, 2, StrLen(text) - 2)                         ; 宽松提取中间全部内容，兼容裸引号
    return true
}

; 把一行正文中的引用式链接展开为行内链接
; 支持：
; - `[文本][标签]`
; - `[文本][]`
; - `[标签]`
; - 对应图片写法 `![alt][img]` / `![img]`
MarkdownExpandReferenceLinksInLine(line, entryMap, &replacementCount) {
    replacementCount := 0                                              ; 调用前先清零，避免累计污染
    out := ""                                                          ; 输出缓冲区：逐字符扫描并重建整行
    index := 1                                                         ; 当前扫描位置（1-based）
    lineLength := StrLen(line)                                         ; 缓存长度，减少重复计算

    while (index <= lineLength) {                                      ; 逐字符扫描，便于同时支持多种写法
        isImage := false                                               ; 标记当前候选是否为图片语法
        tokenStart := index                                            ; 默认认为当前字符就是候选起点
        currentChar := SubStr(line, index, 1)                          ; 读取当前字符做分支判断

        if (currentChar = "!" && SubStr(line, index + 1, 1) = "[") { ; `![alt]...` 图片写法
            isImage := true
            tokenStart := index + 1                                    ; 真正的 `[` 在下一个字符位置
        } else if (currentChar != "[") {                              ; 非链接起始字符：直接照抄
            out .= currentChar
            index += 1
            continue
        }

        textClosePos := MarkdownFindClosingBracket(line, tokenStart)   ; 先解析第一段 `[文本]`
        if !textClosePos {                                              ; 不完整的 `[` 结构按普通文本保留
            out .= currentChar
            index += 1
            continue
        }

        displayText := SubStr(line, tokenStart + 1, textClosePos - tokenStart - 1) ; 取 `[ ]` 内显示文本
        nextChar := SubStr(line, textClosePos + 1, 1)                  ; 决定它是显式引用、折叠引用还是快捷引用

        if (nextChar = "[") {                                          ; 处理 `[文本][标签]` / `[文本][]`
            labelClosePos := MarkdownFindClosingBracket(line, textClosePos + 1)
            if labelClosePos {                                          ; 第二段标签完整，才尝试做引用展开
                rawLabel := SubStr(line, textClosePos + 2, labelClosePos - textClosePos - 2)
                if (rawLabel = "") {                                   ; 折叠写法 `[文本][]` 的标签等于显示文本
                    rawLabel := displayText
                }

                inlineText := ""                                       ; 输出参数：成功构造出的行内链接
                if MarkdownTryBuildInlineReference(displayText, rawLabel, isImage, entryMap, &inlineText) {
                    out .= inlineText                                   ; 命中定义时写入展开后的行内链接
                    replacementCount += 1                               ; 统计一次成功替换
                    index := labelClosePos + 1                          ; 跳过整个 `[文本][标签]` 片段
                    continue
                }
            }
        } else if MarkdownCanExpandShortcutReference(nextChar) {        ; 处理快捷引用 `[标签]`
            inlineText := ""                                            ; 输出参数：成功构造出的行内链接
            if MarkdownTryBuildInlineReference(displayText, displayText, isImage, entryMap, &inlineText) {
                out .= inlineText                                       ; 命中定义时写入行内链接
                replacementCount += 1                                   ; 统计一次成功替换
                index := textClosePos + 1                               ; 跳过整个 `[标签]` 片段
                continue
            }
        }

        consumedLength := textClosePos - index + 1                      ; 未命中定义时，把原片段完整保留
        out .= SubStr(line, index, consumedLength)
        index := textClosePos + 1
    }

    return out                                                          ; 返回这一行的改写结果
}

; 根据标签尝试构造一个行内链接
; 入参：
; - displayText: 链接显示文本 / 图片 alt 文本
; - rawLabel: 用于查定义表的原始标签
; - isImage: true=图片语法，false=普通链接语法
; - entryMap: 定义表映射
; 输出：
; - &inlineText: 成功时返回构造好的 `[text](...)` 或 `![alt](...)`
MarkdownTryBuildInlineReference(displayText, rawLabel, isImage, entryMap, &inlineText) {
    inlineText := ""                                                    ; 先清空输出参数，避免复用旧值
    normalizedLabel := MarkdownNormalizeReferenceLabel(rawLabel)        ; 引用标签大小写不敏感，需要先标准化
    if (normalizedLabel = "") {                                         ; 空标签无法匹配定义
        return false
    }
    if !entryMap.Has(normalizedLabel) {                                 ; 未命中定义表就保持原写法
        return false
    }

    inlineText := MarkdownBuildInlineLink(displayText, entryMap[normalizedLabel], isImage)
    return true                                                         ; 成功构造行内链接
}

; 构造最终的 Markdown 行内链接文本
; 设计细节：
; - URL 一律包成 `<url>`，这样能更稳地兼容括号、查询参数等字符。
; - 标题里的反斜杠与双引号会被转义，保证生成后的 Markdown 更稳。
MarkdownBuildInlineLink(displayText, entry, isImage) {
    prefix := isImage ? "!" : ""                                        ; 图片语法需要保留 `!` 前缀
    linkTarget := "<" entry["url"] ">"                                  ; 统一用尖括号包裹 URL，降低歧义
    title := entry["title"]                                             ; 读取可选标题

    if (title = "") {                                                   ; 没有标题时直接输出最简链接
        return prefix "[" displayText "](" linkTarget ")"
    }

    escapedTitle := MarkdownEscapeLinkTitle(title)                      ; 对标题做必要转义，避免破坏语法
    return prefix "[" displayText "](" linkTarget " " Chr(34) escapedTitle Chr(34) ")"
}

; 判断快捷引用 `[标签]` 后面的字符是否允许展开
; 说明：
; - 如果后面立刻是 `(`，那是行内链接 `[文本](url)`，绝不能误改。
; - 如果后面立刻是 `[`，那是显式引用 `[文本][标签]`，由别的分支处理。
; - 其余场景仅在“结尾 / 空白 / 常见标点”下展开，尽量减少误判。
MarkdownCanExpandShortcutReference(nextChar) {
    if (nextChar = "") {                                                ; 行尾直接结束，是快捷引用的典型形态
        return true
    }
    if (nextChar = "(" || nextChar = "[" || nextChar = ":") {         ; 这些后继字符都不应被当成快捷引用
        return false
    }
    return RegExMatch(nextChar, "^[\s\)\]\}\>\.,;!\?，。；：！？、]$") ; 常见分隔符后才允许展开
}

; 找到从 `[` 开始的那一段对应的第一个“未转义闭合 ]”
; 入参：
; - text: 整段文本
; - openPos: `[` 所在位置（1-based）
; 返回：
; - 闭合 `]` 的位置；若不存在则返回 0
MarkdownFindClosingBracket(text, openPos) {
    escaped := false                                                    ; 标记上一个字符是否为反斜杠转义
    textLength := StrLen(text)                                          ; 缓存长度，避免反复调用

    loop (textLength - openPos) {                                       ; 从 `[` 后面的第一个字符开始扫描
        currentPos := openPos + A_Index                                 ; 当前检查的位置
        ch := SubStr(text, currentPos, 1)                               ; 读取当前位置字符

        if escaped {                                                    ; 被转义的字符不参与语法判断
            escaped := false
            continue
        }
        if (ch = "\") {                                                ; 反斜杠只影响它后面的一个字符
            escaped := true
            continue
        }
        if (ch = "]") {                                                ; 找到第一个未转义闭合 ] 即返回
            return currentPos
        }
    }

    return 0                                                            ; 扫描结束仍未找到，说明结构不完整
}

; 标准化引用标签
; 规则：
; - 去首尾空白。
; - 连续空白折叠为一个空格。
; - 统一转成小写，便于大小写不敏感匹配。
MarkdownNormalizeReferenceLabel(label) {
    normalized := Trim(label, " `t")                                    ; 先清理首尾空白
    normalized := RegExReplace(normalized, "\s+", " ")                 ; Markdown 标签内部空白按单空格归一
    normalized := StrLower(normalized)                                  ; 标签匹配大小写不敏感
    return normalized
}

; 转义行内链接标题中的特殊字符
; 目前只处理两类最关键字符：
; - `\` 需要写成 `\\`
; - `"` 需要写成 `\"`
MarkdownEscapeLinkTitle(title) {
    escaped := StrReplace(title, "\", "\\")                            ; 先转义反斜杠，避免后续再次吃掉
    escaped := StrReplace(escaped, Chr(34), "\" Chr(34))               ; 再转义双引号，保证标题仍合法
    return escaped
}

; 通用字符串数组拼接工具
; 说明：不依赖运行环境是否提供 Array.Join，保持兼容与可控。
MarkdownJoinArray(arr, sep) {
    if (arr.Length = 0) {                                              ; 空数组直接返回空串
        return ""
    }

    out := ""                                                          ; 输出缓冲区
    for index, item in arr {                                           ; 顺序拼接，避免尾部分隔符
        if (index > 1) {
            out .= sep
        }
        out .= item
    }
    return out
}
