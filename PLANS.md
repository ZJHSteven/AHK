# ExecPlan

## 2026-05-21 沙盒中转在资源管理器中偶发拿不到真实路径

### 背景
- 目标：修复 `Ctrl+Alt+C` 在 Windows 资源管理器里已经选中文件时，仍反复提示“未拿到真实文件路径”的问题。
- 现象：`logs\sandbox_bridge.log` 已明确记录多次 `capture begin: exe=explorer.exe`、`capture clipboard: sent Ctrl+C`，但随后都在 `ClipWait(0.8)` 超时，说明问题发生在“让 Explorer 把选中项写进剪贴板”之前，而不是后续 `FileExist()` 过滤。
- 预期结果：资源管理器窗口里优先直接读取当前选中项真实路径，避免依赖 `Send("^c") + ClipWait + A_Clipboard`；同时保留原诊断日志与兜底逻辑，确保桌面或其他场景仍可回退。

### 实现步骤
1. 为 `modules/sandbox_bridge.ahk` 增加“Explorer 原生选中项读取”主路径，通过 Shell COM 找到当前前台 Explorer 窗口并遍历其 `SelectedItems()`。
2. 将现有剪贴板抓取链路收敛为 fallback，只在原生读取失败或当前不是可识别的 Explorer 窗口时启用，并补充更明确的日志。
3. 新增自动化测试，覆盖路径去重、路径采纳规则、Explorer 窗口匹配等可离线验证逻辑；再跑脚本级语法校验与现有测试集。
4. 更新 `PROGRESS.md`，记录这次根因、改法、测试结果与后续手动复现要点。

## 2026-05-13 AHK 托盘热键帮助与 Codex 预设切换

### 背景
- 目标：在 AHK 托盘右键菜单里提供当前热键帮助，并用 AHK 自己管理 Codex 的多套 `auth.json` / `config.toml` 预设。
- 问题：热键越来越多，靠记忆容易忘；外部 cc-switch 切换状态不够可信，切换成功与否不清晰。
- 预期结果：托盘可查看热键、打开 Codex 预设菜单、校验预设、打开预设目录；切换成功后用鼠标附近 ToolTip 明确提示。

### 实现步骤
1. 新增热键帮助显式注册表，不解析注释，不展示禁用模块。
2. 新增 Codex 预设切换模块，读取 `config/codex_profiles/profiles.ini`，真实预设文件放入被忽略的 `secrets` 目录。
3. 切换前备份 live 配置，切换后字节级比对，失败时尝试回滚。
4. 使用 Python helper 校验 JSON/TOML；首次或文件变化后才启动 Python，平时使用缓存。
5. 补自动化测试，覆盖清单解析、当前状态检测、缓存校验、切换与失败保护。

### 执行结果
- 已完成：新增 `modules/hotkey_help.ahk`、`modules/codex_profile_switcher.ahk`、`tools/validate_codex_profile.py`。
- 已完成：新增 `Ctrl+Alt+F12` Codex 预设菜单热键，并在 `main.ahk` 初始化托盘菜单。
- 已完成：新增 `config/codex_profiles/profiles.ini` 与说明文档；真实 secrets/backups/state 已加入 `.gitignore`。
- 已验证：`tests/hotkey_help_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、既有 `tests/markdown_reference_link_inliner_tests.ahk` 均通过。
- 已验证：`AutoHotkey64.exe /ErrorStdOut /Validate .\main.ahk` 通过。

## 2026-03-31 Markdown 引用式链接展开热键

### 背景
- 目标：为剪贴板里的 Markdown 文本提供一个“一键展开引用式链接”的热键。
- 问题：AI 常输出 `[文本][1]` 与文末 `[1]: URL "标题"` 这种引用式链接；一旦正文被单独拷走、或参考链接区被遗漏，正文里的引用就会失效。
- 预期结果：把正文中所有可解析的引用式链接直接改写成行内链接，例如把 `[Zenodo][1]` 改成 `[Zenodo](https://zenodo.org/... "临床医学五年制第十轮 \"十四五\" 规划教材")`，并移除已被消费的引用定义行。

### 实现步骤
1. 新建独立文本处理模块，专门负责：
   - 读取剪贴板文本。
   - 解析 Markdown 引用定义表。
   - 把正文中的引用式链接改写为行内链接。
   - 在未检测到可处理结构时保留原剪贴板并给出提示。
2. 在 `modules/hotkeys.ahk` 中挂载一个新热键入口，保持热键文件只做分发，不堆复杂逻辑。
3. 为文本处理逻辑补自动化测试，覆盖：
   - 普通 `[文本][1]` 引用。
   - 折叠写法 `[1][]`。
   - 大小写标签匹配。
   - 含标题与不含标题的定义。
   - 未命中定义时保持原样。
   - 重复引用、混合普通文本、空剪贴板/无定义输入等边界情况。
4. 更新 `PROGRESS.md`，记录本次决策、已完成项、验证结果和注意事项。

### 测试计划
- 先跑纯函数级自动化测试，确认解析与替换逻辑稳定。
- 再跑脚本级装载测试，确认新增模块被 `#Include` 后不会触发语法错误。
- 若环境允许，再补一次对 `main.ahk` 的无交互加载验证，确保主入口不因新模块报错。

### 执行结果
- 已完成：新增 `modules/markdown_reference_link_inliner.ahk`，并在 `modules/hotkeys.ahk` 接入 `Ctrl+Alt+M` 热键。
- 已完成：补充 `tests/markdown_reference_link_inliner_tests.ahk`，覆盖标准引用、折叠引用、快捷引用、大小写匹配、图片引用、未命中定义、非法定义等场景。
- 已验证：使用 `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe /ErrorStdOut` 运行测试脚本，退出码为 `0`。
- 已验证：额外执行真实样例冒烟测试，确认 `[Zenodo][1]` 会被展开成 `[Zenodo](<https://...> "资料页")`，并移除文末定义行。
