# 项目状态快照（保持短小：建议 <= 200~400 行）

## 当前结论（必须最新）
- 已定位：用户截图里“旧小窗标题是 `Quest 3 快速游戏推荐`、新大窗标题是 `ChatGPT`”这组现象，根因不是默认值再次变大，而是旧窗标题已经变成会话名，未命中早期那条“标题含 `ChatGPT` 才算受管窗口”的脆弱识别规则，导致脚本误判为“当前没有浮窗”并再次 `Run --app=...`。
- 已完成：ChatGPT 浮窗的单实例识别现已不再只依赖标题含 `ChatGPT`；新逻辑会综合“Chrome 顶层窗口 + topmost 样式 + app 标题形态 + 历史矩形接近度”挑选候选，并额外偏向“具体会话名窗口”而不是泛化首页标题。
- 已完成：`Alt+Space` 的切换语义已改成“只要当前受管窗可见，就直接收起；不可见或最小化时才恢复”。因此之前那种“第一次先聚焦，第二次才收起”的行为，不再是当前逻辑预期。
- 已完成：新增启动防抖与互斥锁；如果一轮 `Alt+Space` 还在等待 Chrome app 窗口出现，或你在很短时间里连续触发热键，脚本会直接忽略重复启动请求，避免再开出第二个/第三个窗口。
- 已完成：`ChatGptChromeApplyWindowProtections()` 与恢复流程已补竞态保护；像 `WinSetAlwaysOnTop(1, \"ahk_id ...\")` 这种在窗口瞬间失效时的路径，现在会安全返回并清理状态，而不是再把异常直接抛到界面上。
- 现状：当前代码已经尽量避免“跨虚拟桌面时再次误开新窗”；但它还没有做到“自动把旧窗迁移到当前虚拟桌面”或“自动切到旧窗所在桌面”。也就是说，这一轮修的是“不要再失控地产生新窗”，不是“完整接管 Windows 虚拟桌面路由”。
- 已完成：新增 “ChatGPT Chrome 浮窗” 能力，使用 `Alt+Space` 控制；默认复用 Chrome `Default` Profile，不新建独立 Profile，当前默认以 `app` 模式启动 `https://chatgpt.com/`，并保持 `AlwaysOnTop`。
- 已完成：浮窗首次启动使用 `config/chatgpt_chrome_window.ini` 里的默认小窗尺寸（当前为 `540x760`）；后续用户手动拖动/缩放后的窗口位置与大小会持续写入 `logs/chatgpt_chrome_window_state.ini`，因此再次唤起时会尽量回到上次位置。
- 已完成：右上角关闭按钮当前默认禁用；误点 X 不会再直接关闭并刷新整个 ChatGPT 页面。若要真正关闭，现已统一改为从 AHK 托盘菜单点击“彻底关闭 ChatGPT 浮窗”。
- 已完成：为兼容历史上已经写入本机状态文件的大尺寸矩形，现已新增 `rect_policy_version` 迁移逻辑。旧状态若没有当前策略版本，即使 `window_mode` 已是 `app`，也会自动回退到新的 `540x760` 默认小窗，而不会继续沿用旧大窗。
- 已验证：`modules/chatgpt_chrome_window.ahk` 已兼容 UTF-8 BOM 配置文件；即使 `config/chatgpt_chrome_window.ini` 被编辑器保存成 BOM 版本，也能正常读取 `url / chrome_path / profile_directory / window_mode / startup_timeout_ms / default_width / default_height / always_on_top`。
- 已验证：当前仓库真实配置的非侵入冒烟结果为：`chromePath=C:\Program Files\Google\Chrome\Application\chrome.exe`、`url=https://chatgpt.com/`、`profile=Default`、`mode=app`、`alwaysOnTop=1`、`disableCloseButton=1`；并能正确拼出 `--profile-directory=\"Default\" --app=\"https://chatgpt.com/\" --window-size=540,760 --window-position=1266,532` 这组启动参数。
- 现状：Codex 预设现已从“`custom / right_code` 历史命名”收口到统一的 `OpenAI` provider 命名；`海豹云-天才程序员`、`何一卫`、`Right Code` 都会在共享模板回写时生成 `model_provider = "OpenAI"` 与 `[model_providers.OpenAI]`，`OpenAI Official` 仍保持“顶层不显式写 `model_provider`”的保守策略。
- 已完成：`config/codex_profiles/profiles.ini`、`settings.ini`、本机 secrets 与当前 live `~/.codex/config.toml` 已统一补成四套预设：`openai_official / haibao / heweiyi / right_code`；共享模板成员顺序与托盘菜单顺序也已同步改为 `OpenAI Official -> 海豹云-天才程序员 -> 何一卫 -> Right Code`。
- 已完成：按用户 2026-06-23 的更正，现已只让海豹云使用 IP `http://42.192.94.176:5002`；`何一卫` 与 `Right Code` 改回 URL `https://ai.websee.top`；`OpenAI Official` 恢复为原先的 URL 方案 `https://code.rpgame.net`，不再误写成统一 IP。
- 现状：已新增 AHK 托盘菜单能力：`查看热键` 使用显式注册表展示当前加载热键，`Codex 预设` 支持从托盘或 `Ctrl+Alt+F12` 弹出菜单切换多套 Codex 配置；沙盒中转 `Ctrl+Alt+C` 已升级为“Explorer 原生选中读取优先、剪贴板兜底”，并额外兼容“右侧预览窗格/第三方预览处理器抢焦点”的情况。
- 已完成：Codex 预设切换现在会在真正覆盖目标预设前，先把当前 live `auth.json + config.toml` 整文件回写到来源预设；即使 live `config.toml` 已因用户运行时手改而不再字节匹配任何预设，也会继续回退到 `state.ini` 中的 `last_switch` 作为来源预设兜底，避免“插件/MCP/provider 改了却在下次切回时被旧预设整文件覆盖”。
- 已完成：新增 `config/codex_profiles/settings.ini` 与四套预设的 provider 模板元数据。开启 `shared_template.enabled=1` 后，任意一套成员预设的 live `config.toml` 都会被视为“公共模板来源”，同步追平到 `openai_official / haibao / heweiyi / right_code` 四套预设，仅保留各自 provider 差异。
- 已完成：已核对 `OpenAI Official` 与海豹云/当前 live 的结构差异；确认 MCP 变少的根因就是 `openai_official/config.toml` 确实缺少 `context7 / github / figma / stitch` 等 MCP 定义，且插件清单也比当前 live 更少。
- 已完成：四套预设现已按“plain MCP 为真源”统一补齐 `context7 / github / cloudflare-api`；`Right Code` 与 `何一卫` 均朝海豹云结构对齐，仅保留 provider 差异。
- 已完成：为避免和已迁移到全局的 skills / MCP 重复，`github@openai-curated`、`cloudflare@openai-curated` 已从三套预设里改为关闭；`OpenAI Official` 额外关闭了用户点名的 `canva / figma / stripe / vercel` plugin。
- 已完成：新增 Codex 预设清单 `config/codex_profiles/profiles.ini`，当前包含 `OpenAI Official`、`海豹云-天才程序员`、`何一卫`、`Right Code` 四套；真实 `auth.json/config.toml` 放入已忽略的 `secrets` 目录，不进入 Git。
- 已完成：切换流程会按需校验 JSON/TOML、切换前备份 live 配置、写入后做字节级比对，成功/失败只用鼠标附近 ToolTip 提示。
- 已完成：`modules/sandbox_bridge.ahk` 新增 Shell COM 读取路径：当前前台位于资源管理器主窗口或其子窗口时，优先通过 `Shell.Application.Windows -> Document.SelectedItems() -> FolderItem.Path` 直接读取选中项；原 `Send("^c") + ClipWait + A_Clipboard` 方案保留为 fallback，并继续写详细日志。
- 已完成：修复 Shell COM 集合枚举 bug。此前日志连续报 `This value of type "Integer" has no property named "HWND"`，根因是把 `ShellWindows` 的迭代结果误当成窗口对象；现已改为 `Count + Item(i)` 方式读取。
- 已完成：新增“根祖先窗口句柄”匹配逻辑。当前焦点若落在预览窗格、列表子控件或第三方预览处理器上，会先通过 `GetAncestor(..., GA_ROOT)` 回到最外层 Explorer 主窗口，再与 `ShellWindows` 匹配。
- 已完成：新增 `tests/sandbox_bridge_tests.ahk`，覆盖 Explorer 窗口匹配、候选路径去重、缺失路径过滤、匹配窗口选中项解析，以及 `Count + Item(i)` 形式的 COM 集合访问。
- 已验证：`tests/hotkey_help_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、`tests/markdown_reference_link_inliner_tests.ahk` 全部通过；其中热键帮助测试已覆盖托盘菜单初始化路径，`main.ahk /Validate` 也已通过，且相关测试入口已显式 include `utils.ahk` 消除 `Toast` 静态警告；Python TOML 校验已兼容 Windows 常见 UTF-8 BOM。
- 已验证：本轮 `OpenAI` 命名收口后，`tests\codex_profile_switcher_tests.ahk`、`main.ahk /Validate`、四套本机预设 `haibao / openai_official / right_code / heweiyi` 的 `validate_codex_profile.py`，以及当前 live `%USERPROFILE%\.codex\auth.json + config.toml` 校验均已通过。
- 已验证：本轮“只有海豹云使用 `http://42.192.94.176:5002`，`何一卫 / Right Code` 使用 `https://ai.websee.top`，`OpenAI Official` 保持 `https://code.rpgame.net`”的修正已通过共享模板回写测试与四套本机配置校验，不会再把所有预设统一刷成同一个 IP。
- 已验证：`logs\sandbox_bridge.log` 已明确证明旧问题断在 `ClipWait(0.8)` 超时，而不是后续 `FileExist()`；用户补充“右侧预览窗格打开就不行、关掉就行”后，又结合 Microsoft Learn 的 Preview Handler 文档确认：预览窗格本就是宿主 + 预览处理器协作的子窗口区域，这条线索与“焦点落到子窗口/第三方预览组件”高度一致。
- 已验证：用 PowerShell + Shell COM 对真实 Explorer 窗口做了现场探针，已能读到当前窗口句柄 `393424`、文件夹 `C:\Users\ZJHSteven\Downloads\__AHK_Transit__` 与选中项 `C:\Users\ZJHSteven\Downloads\__AHK_Transit__\张家赫.pptx`，说明修正后的主路径在这台机器上可用。
- 已验证：`tests\sandbox_bridge_tests.ahk`、`tests\hotkey_help_tests.ahk`、`tests\codex_profile_switcher_tests.ahk`、`tests\markdown_reference_link_inliner_tests.ahk` 与 `main.ahk /Validate` 全部通过。
- 已验证：本轮已补“auth refresh 后仍能识别当前预设”、“切换前先回写来源整文件”与“config 已漂移时仍可依赖 last_switch 回写来源整文件”三条自动化用例；落地后需要再次执行 `tests\codex_profile_switcher_tests.ahk` 与 `main.ahk /Validate` 做回归确认。
- 已验证：Cloudflare 插件缓存当前真实结构是 `skills + .mcp.json`，其中 `.mcp.json` 暴露的就是 `cloudflare-api -> https://mcp.cloudflare.com/mcp`；GitHub 插件缓存真实结构则是 `skills + .app.json`，说明把 `cloudflare/github` plugin 与 plain MCP 同时打开，确实会形成重复入口。
- 下一步：执行一轮 Codex 预设专项回归：确认 `何一卫` 能在托盘菜单里被识别，确认切到海豹云后 live `config.toml` 仅海豹云使用 `http://42.192.94.176:5002`，而切到 `何一卫 / RC / OpenAI Official` 后会分别恢复各自 URL，再回头继续 Explorer 预览窗格的手工复现。
- 下一步：如果用户后续确认还要保留真正的多标签页工作流，再把 `config/chatgpt_chrome_window.ini -> window_mode` 从 `app` 切回 `window`，或补一套“app / window 双实例”切换策略。
- 下一步：若用户后续明确要求“切换虚拟桌面后，Alt+Space 必须自动把同一个浮窗带过来，或自动切到它所在桌面”，则需要单独接入 Windows `IVirtualDesktopManager` 路径做桌面归属判断；这会是下一轮独立功能，不属于本轮“单实例修复”的完成范围。

## 关键决策与理由（防止“吃书”）
- 决策A：热键帮助采用显式注册表，不从注释自动解析。
  原因：注释格式适合人读，不适合当稳定数据源；显式注册表能保证展示内容可控，尤其适合后续给新人维护。
- 决策B：Codex 预设切换采用整文件替换，而不是只改局部字段。
  原因：`auth.json` 与 `config.toml` 的真实结构可能随 Codex 变化；整文件预设最直观，切换后也能直接字节比对确认成功。
- 决策C：真实预设文件不提交，只提交清单、代码和说明。
  原因：`auth.json` 可能包含 API Key / OAuth token，进入 Git 历史后很难彻底清理。
- 决策D：Codex 预设切换默认自动回写来源预设的整份 `auth.json + config.toml`，不再区分“凭据文件”和“配置文件”。
  原因：这台机器上的实际使用方式并不是“预设永远只手动维护”，而是会在 live 运行态中真实安装/关闭插件、增减 MCP、调整 provider / model；如果只回写 auth，下一次切回预设时这些 live 配置就会被旧 `config.toml` 全量覆盖，等于改了白改。
- 决策E：托盘菜单对“当前预设”的展示仍保持保守识别；只有 exact / config_only 命中才标 `[当前]`，不会因为 `last_switch` 兜底而误报。
  原因：`last_switch` 只用于“切换前尽量保存当前 live 演化结果”，不代表 live 当前仍与该预设一致；把它直接拿来当 UI 当前态会误导用户。
- 决策F：三套 provider 预设支持“通用模板同步”开关；开关开启后，公共 `config.toml` 内容以当前 live 为真源，自动追平到模板组内所有预设，仅保留各自 provider patch。
  原因：用户实际诉求不是维护三份长期漂移的配置，而是“换 provider 不换其余内容”；因此 provider 之外的插件、MCP、marketplaces、projects、模型参数都应跟随当前 live 一起同步。
- 决策F.1：中转 provider 的逻辑名统一使用 `OpenAI`，不再沿用 `custom / right_code`。
  原因：共享模板会按 `profiles.ini` 重建 provider block；若逻辑名不统一，live 手改后仍会在下一次切换被旧命名覆盖，用户也难以从配置表面判断几套中转其实是同一种 provider。
- 决策F.2：只有海豹云改成 `http://42.192.94.176:5002`；`何一卫` 与 `Right Code` 继续使用 `https://ai.websee.top`，`OpenAI Official` 继续保持自己的原始 URL。
  原因：用户已明确纠正“只有海豹云用 IP”；现场探测也确认 `http://42.192.94.176:5002` 返回 `200`、`https://ai.websee.top` 返回 `200`，因此当前最稳做法是按预设逐套保留各自地址，而不是再强行统一。
- 决策G：Codex provider 预设当前以 plain `mcp_servers.context7 / github / cloudflare-api` 为主要真源，而不是依赖同名 curated plugin 继续二次提供重复 skills/MCP。
  原因：这台机器上 Cloudflare plugin 真实结构是 `skills + .mcp.json`，GitHub plugin 真实结构是 `skills + .app.json`；而相关 skills 已迁到全局，若 plugin 与 plain MCP 同时启用，入口会重复、状态更混乱。
- 决策H：资源管理器场景优先直接读取 Explorer 选中项，不再把“真实路径获取”完全绑定到剪贴板复制链路。
  原因：本次现场日志多次证明前台已是 `explorer.exe`、`Ctrl+C` 已发送，但 `ClipWait` 仍超时；继续只调等待时间没有意义，应该改为更贴近 Explorer 内部状态的读取方式。
- 决策I：Explorer 匹配以“根祖先窗口”而不是“瞬时焦点子窗口”为准。
  原因：右侧预览窗格、文件列表控件、第三方 Preview Handler 都可能拿走前台焦点；若只认瞬时子窗口，脚本会错误地认为自己“不在资源管理器主窗口”。
- 决策J：ChatGPT 浮窗当前默认走 Chrome `app` 模式，默认尺寸收紧为 `540x760`。
  原因：用户在第一轮落地后明确反馈“默认大小实在太大”，并希望先优先试更像桌面小窗的 app 形态；因此当前先按“小窗优先”而不是“多标签页优先”收口。
- 决策K：ChatGPT 浮窗的位置/大小状态单独写入 `logs/chatgpt_chrome_window_state.ini`，不混写回 `config/chatgpt_chrome_window.ini`。
  原因：窗口状态是高频变化的运行态数据，若混到静态配置文件里，会让真正需要 review 的功能配置和本机状态搅在一起。
- 决策L：ChatGPT 浮窗默认禁用右上角关闭按钮，只允许从 AHK 托盘菜单显式彻底关闭。
  原因：用户明确不希望误点 X 后让整个页面重新刷新；对外部 Chrome 窗口来说，最稳妥的防误关方案不是“关后再救”，而是直接禁用 `SC_CLOSE`。
- 决策M：ChatGPT 浮窗状态新增 `rect_policy_version`；旧状态版本不匹配时，忽略历史矩形并回退到新的默认小窗尺寸。
  原因：单纯改配置无法覆盖已经写入本机状态文件的旧大窗矩形；需要一个一次性迁移闸门，才能让“新默认值”真正生效。
- 决策N：ChatGPT 浮窗的“重新接管现有窗口”不再只依赖标题含 `ChatGPT`，而是结合 topmost 样式、app 标题形态与历史矩形接近度综合打分，并偏向具体会话名窗口。
  原因：app 模式下的真实窗口标题会变成会话名，例如 `Quest 3 快速游戏推荐`；若仍只认 `ChatGPT`，脚本必然会误判旧窗不存在并重复开窗。
- 决策O：`Alt+Space` 的切换语义以“可见性”为核心，而不是“是否前台”。
  原因：用户的真实心智模型是“这就是一个开关”；如果窗口已经可见，即使它当前没焦点，也应一键收起，不该先激活再按第二次。

## 常见坑 / 复现方法
- 坑1：切换 Codex 配置后，已经打开的 Codex 终端通常不会自动重新读取配置；需要关闭并重新打开终端。
- 坑2：`OpenAI Official` 和 `Right Code` 初始只在 `profiles.ini` 里占位；没有补齐对应 `secrets/<profile_id>/auth.json` 与 `config.toml` 前，菜单会显示但禁用。
- 坑3：如果 live `.codex` 被外部手动改到不匹配任何预设，托盘菜单不会误报“当前”；下次切换仍会先备份这个未知状态，再写入目标预设。
- 坑3.1：虽然托盘菜单不会把“已经漂移的 live”误标成当前预设，但切换前的同步流程现在会依赖 `state.ini -> last_switch` 兜底，把这份 live 整文件回写到最近一次成功切入的来源预设；这是为了保住用户运行期手改的配置，不是 UI 当前态判定。
- 坑3.2：开启 `settings.ini -> shared_template.enabled=1` 后，来源预设的 live `config.toml` 会自动扩散到模板组内其他成员预设；因此如果只是临时实验某个 provider 的私有配置，应先关掉该开关，避免把实验配置同步给另外三套预设。
- 坑3.3：现在 `haibao / right_code / heweiyi` 的顶层 `model_provider` 都会被强制写成 `OpenAI`；如果只手改某份 secrets 或 live 文件里的旧 `custom/right_code` 字样，不同步更新 `profiles.ini`，下一次切换仍会被共享模板改回。
- 坑3.4：共享模板并不意味着四套预设会共用同一个 `base_url`；`profiles.ini` 里的 `template_provider_base_url` 仍是每套预设自己的真源。只要这里配错，切换时就会再次把 live 写回错误地址。
- 坑4：`OpenAI Official` 的 `auth.json` 不是静态 API Key 文件，还会包含 `auth_mode / last_refresh / tokens`；如果切换器只做“预设覆盖 live”，不做“离开前回写来源 auth”，下次切回就会被旧 refresh token 覆盖。
- 坑5：`cloudflare@openai-curated` 与 `github@openai-curated` 并不只是“一个按钮开关”那么简单：前者底层是 `skills + .mcp.json`，后者底层是 `skills + .app.json`。如果 plain MCP 已经单独接好、相关 skills 又迁到了全局，再继续开 plugin 只会制造重复入口。
- 坑6：沙盒中转 `Ctrl+Alt+C` 若在资源管理器已选中文件但仍提示未拿到路径，先看 `logs/sandbox_bridge.log`，重点检查活动窗口、剪贴板文本长度、候选路径和 `FileExist()` 结果。
- 坑7：如果是资源管理器窗口，最新日志里应优先关注 `capture explorer:` 分支；只有当这里明确返回 0 项时，脚本才会退回到旧的 `capture clipboard:` 分支。
- 坑8：如果右侧预览窗格启用了第三方预览器（例如 WPS 提供的 Office 预览），问题不一定表现为“窗口不是 Explorer”；更常见的是焦点落到 Explorer 内部的预览子窗口，导致旧的 `Ctrl+C` 抓取链路更容易失效。因此这类问题要优先看 `match_hwnd` 和 `match_exe`，不要只盯 `hwnd/exe/title` 的第一层日志。
- 坑9：`Alt+Space` 管理的是“本模块最后一次启动/识别到的 ChatGPT Chrome 窗口”，不是所有 Chrome 窗口的全局开关；如果用户手动把标签拖成新窗口、或同时保留多个标题都含 `ChatGPT` 的窗口，脚本只能做启发式重识别，不能像独立 Profile 那样 100% 强隔离。
- 坑10：当前默认已切到 `app`；如果之后又想保留多个标签页，需要把 `config/chatgpt_chrome_window.ini` 里的 `window_mode` 改回 `window`，否则标签页能力会继续受限。这是 Chrome 启动模式本身的取舍，不是 AHK 逻辑 bug。
- 坑11：旧的 `logs/chatgpt_chrome_window_state.ini` 可能仍保留历史大窗的 `x/y/w/h`；但只要里面的 `rect_policy_version` 还不是当前值，这些旧尺寸就会被自动忽略。这是预期行为，不代表状态迁移失效。
- 坑12：当前这轮修复的目标是“防止失控重复开窗并修正 Alt+Space 切换语义”，不是“让窗口自动跨虚拟桌面迁移”。如果用户把浮窗留在别的虚拟桌面，本轮代码会尽量不再新开重复窗，但不保证它会像某些原生 App 一样自动跟桌面切换。
