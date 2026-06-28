# ExecPlan

## 2026-06-28 用 AHK 管理 Chrome 版 ChatGPT 浮动窗

### 背景
- 目标：用 AHK + Chrome 替代 Windows 官方 ChatGPT Desktop App，提供一个可用 `Alt+Space` 快速唤起/收起的置顶浮动窗。
- 用户刚确认的硬需求：
  - 热键固定为 `Alt+Space`。
  - 浮动窗必须 `Always on Top`，并尽量像“小窗工作台”一样随时压在别的窗口之上。
  - 首次启动有默认大小，但后续允许手动拖动、缩放。
  - 再次收起/唤起后，要记住上一次的窗口位置和尺寸。
  - 必须复用 Chrome 的默认正常 Profile，不新建独立 Profile。
- 当前取舍点：
  - 若走 Chrome `--app=` 模式，更像桌面 App，但天然不适合“保留多个标签页”。
  - 若走普通 `--new-window` 模式，可以保留标签页，但窗口外观会更像浏览器。
- 本轮决策：
  - 默认先实现“普通 Chrome 专用窗口模式”，保证多个标签页可用、复用默认 Profile、由 AHK 接管窗口显示/隐藏/置顶/位置记忆。
  - 同时把 `app` 模式做成配置项，方便后续若用户确认要更纯的 App 外观时，只改配置、不重写逻辑。

### 预期结果
- 新增独立模块管理 ChatGPT Chrome 浮窗，不把复杂逻辑堆进 `modules/hotkeys.ahk`。
- `Alt+Space`：
  - 若浮窗不存在：启动 Chrome 默认 Profile 并打开 ChatGPT。
  - 若浮窗已存在但被隐藏/最小化：恢复到上次位置和尺寸并激活。
  - 若浮窗正在前台：保存最新位置和尺寸后隐藏。
  - 若浮窗存在但不在前台：激活并保持置顶。
- 窗口位置/尺寸状态写入本地状态文件，不污染功能配置文件。
- 补测试覆盖配置解析、启动参数拼装、窗口矩形计算等纯逻辑，并执行主脚本语法校验与现有回归测试。

### 实现步骤
1. 新增 `config/chatgpt_chrome_window.ini`，把 URL、窗口模式、默认尺寸、Profile 名称等放进可读配置。
2. 新增 `modules/chatgpt_chrome_window.ahk`：
   - 自动探测本机 Chrome 路径。
   - 拼接 `Default` Profile 的启动参数。
   - 管理浮窗的显示、隐藏、置顶、位置恢复与状态持久化。
   - 用轻量轮询持续记录用户手动拖动/缩放后的最新位置。
3. 在 `modules/hotkeys.ahk` 挂载 `Alt+Space`，并在 `modules/hotkey_help.ahk` 补帮助说明。
4. 新增 `tests/chatgpt_chrome_window_tests.ahk`，覆盖：
   - `window/app` 模式归一化；
   - Chrome 启动参数拼装；
   - 默认窗口矩形居中与边界收敛；
   - 配置缺省值回退。
5. 更新 `PROGRESS.md`，记录“默认先走普通窗口模式、app 模式保留为配置项”的理由、已验证项与手工使用方法。

### 执行结果
- 已完成：新增 `config/chatgpt_chrome_window.ini`、`modules/chatgpt_chrome_window.ahk`、`tests/chatgpt_chrome_window_tests.ahk`。
- 已完成：`Alt+Space` 已接入 `modules/hotkeys.ahk`，`modules/hotkey_help.ahk` 与 `tests/hotkey_help_tests.ahk` 也已同步。
- 已完成：配置读取已兼容 UTF-8 BOM，避免用户用常见编辑器保存后 `IniRead` 失效。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk`、`tests/hotkey_help_tests.ahk`、`tests/markdown_reference_link_inliner_tests.ahk`、`tests/sandbox_bridge_tests.ahk`、`tests/codex_profile_switcher_tests.ahk` 与 `main.ahk /Validate` 全部通过。
- 已验证：针对仓库内真实 `config/chatgpt_chrome_window.ini` 的非侵入冒烟已输出实际启动命令，确认当前默认行为为：`Default` Profile + `window` 模式 + `1180x820` + `AlwaysOnTop=1`。

## 2026-06-23 Codex 中转预设统一改名为 OpenAI 并新增“何意味”

### 背景
- 目标：把现有中转型 Codex 预设的 provider 标识统一成 `OpenAI`，避免 `custom / right_code` 这类历史名字继续在 live `config.toml` 与共享模板回写里来回漂移。
- 新需求：
  - `海豹云-天才程序员` 与 `Right Code` 两套中转预设，后续都使用同一套 provider 名称：`OpenAI`。
  - `OpenAI Official` 仍保持“顶层不显式写 `model_provider`”的策略，但其 provider section 也要与模板侧统一到 `OpenAI`。
  - 新增一套显示名为 `何一卫` 的中转预设，并按用户提供的 `OPENAI_API_KEY` 与 provider 模板初始化。
  - 地址分配按用户 2026-06-23 的更正执行：只有 `海豹云-天才程序员` 改为 `http://42.192.94.176:5002`；`何一卫` 与 `Right Code` 保持 URL `https://ai.websee.top`；`OpenAI Official` 恢复为原先的 URL 方案，不跟随海豹云切到 IP。
- 当前问题：
  - `shared_template.enabled=1` 开启后，切换流程会按 `profiles.ini` 中声明的 provider patch 重建 `[model_providers.*]`，因此只改 live 或 secrets 里的单份 `config.toml` 不足以持久化。
  - 现有测试夹具与断言仍把 `custom / right_code` 视为预期值；若不一起更新，后续回归测试会全部失真。
- 预期结果：
  - `profiles.ini`、本机 secrets、live 配置与测试预期统一到新的 `OpenAI` 命名。
  - 新增 `何一卫` 预设后，托盘菜单与校验流程能正常识别它。
  - 共享模板同步后，各预设只保留“是否顶层写 `model_provider`”与“各自 base_url”这类最小差异，不再保留旧命名，也不会再把所有预设误写成同一个 IP。

### 实现步骤
1. 更新 `config/codex_profiles/profiles.ini`，把中转预设的 `template_model_provider` / `template_provider_section_name` 统一改成 `OpenAI`，并补入 `何意味` 预设元数据。
2. 同步修正本机 `config/codex_profiles/secrets/*/config.toml` 与新增 `heweiyi` secrets，使现存预设和新预设在下次切换前就处于一致结构。
3. 补齐或更新 `auth.json` / `config.toml` 语法校验与 `tests/codex_profile_switcher_tests.ahk` 夹具，覆盖“共享模板把中转预设统一改写成 OpenAI provider”和“新增何意味预设可被识别”。
4. 更新 `PROGRESS.md` 记录本轮 provider 命名与新预设决策，并执行 `tests\codex_profile_switcher_tests.ahk`、`main.ahk /Validate` 与 Python 配置校验，确认没有回归。

## 2026-06-07 Codex 三套预设新增通用模板同步开关

### 背景
- 目标：把 `OpenAI Official`、`海豹云-天才程序员`、`Right Code` 升级成“同一套公共模板 + 各自 provider 差异”的同步模式。
- 新需求：用户确认这三套预设本质上只是“换 provider”，而不是维护三份彼此漂移的独立配置。开启开关后，只要在任意一套预设的 live 运行态里改了公共配置（插件、MCP、模型参数、projects、marketplaces 等），切出时都应自动同步到三套预设；三者只保留 provider 相关差异。
- 当前问题：
  - `OpenAI Official` 目前已大体追平海豹云，但 `Right Code` 仍明显落后。
  - 现有“整文件回写来源预设”只能保证当前来源不丢改动，不能把公共改动自动扩散到另外两套预设。
- 预期结果：
  - 新增一个可配置的“通用模板同步”开关。
  - 开启后，任一来源 live 的公共 `config.toml` 变更会同步施加到三套预设。
  - 三套预设只保留各自 provider 差异；其余结构与开关矩阵自动追平。

### 实现步骤
1. 在 `config/codex_profiles` 下新增 `settings.ini`，提供 `shared_template.enabled` 与成员列表配置。
2. 扩展 `profiles.ini`，为三套预设补 provider 模板元数据（top-level `model_provider` 是否存在、provider section 名称、base_url、wire_api、requires_openai_auth`）。
3. 在 `modules/codex_profile_switcher.ahk` 中实现：
   - 读取通用模板设置。
   - 把 live `config.toml` 作为公共模板来源。
   - 对模板组内每套预设套用自己的 provider patch，再写回各自 `config.toml`。
   - `auth.json` 仍只回写当前来源预设，不跨 provider 扩散。
4. 补测试覆盖“模板关闭时只回写来源”、“模板开启时三套公共配置追平且只保留 provider 差异”，并更新 `README/PROGRESS`。

## 2026-06-06 Codex 预设切换改为整文件回填并追平最近运行态

### 背景
- 目标：把 Codex 预设切换从“只回写来源 `auth.json`”升级为“离开当前预设前，把 live `auth.json + config.toml` 整文件一起回写到来源预设”。
- 新证据：用户确认自己会在 live 运行过程中手动安装/关闭插件、调整 provider / model / MCP 等；如果切换器只回写 `auth.json`，那么这些 live `config.toml` 改动在下一次切回预设时会被旧预设整文件覆盖，等于“改了白改”。
- 已知风险：当 live `config.toml` 已被手改到不再字节匹配任一预设时，原来的 `DetectActiveMatch()` 会失配，导致连来源预设都认不出来，从而无法回写。
- 预期结果：
  - 切换前优先整文件回写当前 live `auth.json + config.toml` 到来源预设。
  - 若 live 已漂移到无法再精确匹配预设，则回退到 `state.ini` 里的 `last_switch` 作为来源预设兜底。
  - 保持托盘“当前预设”标记的保守策略，不因 `last_switch` 兜底而误报当前态。
  - 结合最近备份，把 `OpenAI Official` 预设追到目前可确认的最新运行态。

### 实现步骤
1. 扩展 `modules/codex_profile_switcher.ahk`：新增“来源预设解析”兜底逻辑，切换前改为整文件同步 `auth.json + config.toml`，并在回写后做双文件字节比对。
2. 保持 `CodexProfilesDetectActiveMatch()` 只做保守识别；新增仅供切换流程使用的 `last_switch` 回退函数，避免托盘状态误报。
3. 补测试：覆盖“config 漂移后仍可依赖 last_switch 回写来源预设整文件”、“切换前会同步来源 config”、“失败回滚不污染 live”。
4. 更新 `PROGRESS.md` 记录策略变化，并把本机 `OpenAI Official` 预设追到最近一次可确认的 OpenAI 运行态备份。

## 2026-05-29 Codex 三套预设统一 MCP 真源并收敛重复插件

### 背景
- 目标：按用户刚确认的策略，统一 `OpenAI Official`、`海豹云-天才程序员`、`Right Code` 三套预设的 MCP / plugin 开关，避免“同一套 skills 已经迁到全局，plugin 里又开一份”造成重复。
- 已知要求：
  - 三套预设都至少显式具备并启用 `context7`、`github`、`cloudflare-api` 三个 MCP。
  - 其余现有 MCP 默认保持关闭，避免无意消耗或重复入口。
  - `Right Code` 的整体结构尽量向海豹云对齐，只保留 provider 差异。
  - `OpenAI Official` 里用户点名的 `canva / figma / github / stripe / vercel / cloudflare` plugin 应关闭。
- 预期结果：三套预设都能通过 `validate_codex_profile.py` 校验；`OpenAI Official` 不再因为旧瘦配置缺 MCP，也不再因为多开重复 plugin 导致状态混乱。

### 实现步骤
1. 读取当前 plugin cache，确认 Cloudflare 走 `skills + .mcp.json`，GitHub 走 `skills + .app.json`，据此解释“为什么 plugin 与 MCP 会重复”。
2. 直接修正三套本机 secrets 里的 `config.toml`：
   - 三套都补齐并启用 `context7 / github / cloudflare-api`。
   - 其余已有 MCP 显式保持 `enabled = false`。
   - `Right Code` 向海豹云看齐，仅保留 provider 差异。
3. 收敛 plugin 开关，优先关闭与已迁移全局 skills / 新 MCP 路径重复的项；其中 `OpenAI Official` 至少关闭用户点名的重复 plugin。
4. 更新 `PROGRESS.md` 记录这轮“以 MCP 为真源、重复 plugin 收敛”的最新结论，并执行三套配置校验。

## 2026-05-29 Codex 预设切换补齐 auth 回写与 OpenAI Official MCP 修复

### 背景
- 目标：修复 Codex 预设切换里的两个真实使用问题。
- 问题1：当前 `modules/codex_profile_switcher.ahk` 只会把目标预设覆盖到 live `~/.codex`，不会在“离开当前预设”时把最新 live `auth.json` 回写到来源预设；而 `OpenAI Official` 的 refresh token 会自动刷新，导致下次切回时又被旧 token 覆盖。
- 问题2：`config/codex_profiles/secrets/openai_official/config.toml` 与海豹云/当前 live 的插件与 MCP 清单不一致，当前缺少 `context7 / github / figma / stitch` 等 MCP，因此切到 `OpenAI Official` 后会看到 MCP 变少。
- 预期结果：切换时先识别当前 live 属于哪套预设，再把当前 live `auth.json`（必要时连同 `config.toml`）同步回来源预设；同时补齐 `OpenAI Official` 预设中缺失的 MCP/插件配置，并补测试防止回归。

### 实现步骤
1. 扩展 Codex 预设切换模块，在执行覆盖前先检测当前 active profile，并把当前 live 文件安全同步回对应预设目录。
2. 约束同步策略：至少保证 `auth.json` 始终回写最新版本；若 live 当前正好属于该预设且 `config.toml` 也发生真实变更，则允许一并同步，避免预设长期漂移。
3. 补自动化测试，覆盖“切换前回写来源预设 auth”、“切换失败不污染 live”、“回写后下一次切换仍能命中最新 token”。
4. 修复本机 `OpenAI Official` 预设配置，补齐缺失的 MCP/插件条目，并再次核对与 live/海豹云的结构差异。
5. 更新 `PROGRESS.md`，记录这次根因、配置差异结论与验证结果。

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

### 2026-05-21 追加修正
- 新证据：用户补充“右侧预览窗格打开就不行，关闭就行”，符合 Preview Handler 抢焦点/改变活动子窗口的特征。
- 新问题：`logs\sandbox_bridge.log` 显示当前实现还存在 Shell COM 枚举 bug，连续报 `This value of type "Integer" has no property named "HWND"`，导致 Explorer 原生读取分支实际上没有生效。
- 追加动作：
1. 修复 Shell COM 窗口集合枚举方式，确保真实遍历到 `ShellWindows.Item(i)` 返回的窗口对象，而不是把索引当窗口对象。
2. 在匹配 Explorer 窗口时，引入前台窗口根祖先 `HWND` 识别，避免预览窗格内的子窗口/第三方预览处理器抢焦点后，脚本误认为“不在资源管理器主窗口”。
3. 追加测试与日志，重点覆盖“数组测试桩 + COM 集合式访问”两种路径，以及根窗口匹配日志。

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
