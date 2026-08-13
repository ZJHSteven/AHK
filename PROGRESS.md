# 项目状态快照（保持短小：建议 <= 200~400 行）

## 当前结论（必须最新）
- 已完成磁盘代码改造：watcher 就绪判断、构建命令、构建函数、日志和提示均已升级到 Stage 5；
  就绪门槛新增 real CLI、Shim、路由配置三个 64 位 SHA-256 manifest 字段检查。
- 已扩展测试夹具：除空目录和错误 architecture 外，新增错误版本、缺模型、无效哈希、缺必要文件，
  并明确拒绝构建命令残留 `-StageName stage4`。自动测试结果待本轮随后执行并回填。
- 正在将 Codex Desktop watcher 从 Stage 4 发布契约升级到 Stage 5。当前运行中的 Stable 已确认是
  `stage5\app\ChatGPT.exe -> resources\codex.exe -> resources\codex-real.exe`，但磁盘 watcher 仍构建
  `-StageName stage4`；若不修正，下次 Store 更新可能发布缺少协作模式、resume 和历史修复的旧契约。
- 本轮约束：只修改磁盘代码、测试与文档，不关闭、不替换、不 Reload 当前管理员 AHK；完成后由用户手动 Reload。
- 已完成并验证 Codex Desktop watcher 的 Stage 4 迁移：就绪判断要求 `protocol-observer-stage4` manifest、无密钥路由配置、shim、real CLI、原版 app.asar、全部 helper，以及何意味 Sol/Terra 与 DeepSeek Flash 三个已验收模型；构建命令使用 `-StageName stage4 -PublishState` 后再刷新 StableOnly。
- watcher 单元测试与真实 AHK -> PowerShell Stage 4 集成测试均退出码 0；补丁器 Stage 4 已发布为 Stable，失败时仍由 staging/manifest 门槛保留上一版可用 Stable。
- 当前常驻管理员 AHK 于 2026-08-13 00:14 重启，已解决旧实例并存；但它早于本轮 Stage 4 watcher 源码修改，因此内存中仍是 Stage 1 watcher。磁盘代码会在用户下次正常重启 AHK 后加载，不应再用非管理员 `/Validate` 强行替换管理员实例。
- 进程收口时发现两个 watcher 测试解释器未显式退出；已在两个测试入口末尾增加 `ExitApp(0)`，后续改用 `Start-Process -Wait` 获取真实退出码，防止测试进程被误认为第二个常驻实例。
- 已验证：Store 仍为 `26.721.4979.0`；stable/no-lock 已强制重建成功，重新解包后 history 10 处、resume provider 1 处、token usage 1 处、provider 转发 2 处、no-lock 1 处均符合预期。
- 已验证：修复后只运行一份 AHK；连续跨过两个一分钟轮询周期，watcher 日志没有新增失败或重复构建，版本比较与正式产物检查均为 true。
- 已完成：修复 Store 版本末尾 CRLF 污染。PowerShell 查询改为 `Set-Content -NoNewline`，AHK 再用显式字符集清除空格、Tab、CR、LF；真实版本现在可直接命中正式 stable/no-lock 目录。
- 已完成：watcher 测试新增 CR/LF 拒绝、版本规范化边界和“真实读取版本对应四个正式产物完整”检查，避免正则结尾锚点再次漏掉尾随换行。
- 已定位并修复：Watch 反复构建失败的直接原因是它用 Windows PowerShell 5.1 读取 UTF-8 无 BOM 的 `Build-CodexDesktop.ps1`，中文文本被按旧代码页解码并触发 `UnexpectedToken`；构建入口现已明确改用 `C:\Program Files\PowerShell\7\pwsh.exe`。
- 已完成：Codex Desktop watcher 新增独立日志 `logs/codex_desktop_patch_watcher.log`；同一版本构建失败后会退避 30 分钟，完全相同的错误只提示一次，不再每分钟重复构建和弹窗。
- 已验证：失败退避新增边界测试，覆盖首次失败提示、同错误去重、新版本不继承退避、30 分钟后恢复重试；watcher 专项测试与 `main.ahk /Validate` 均退出码 0。
- Codex Desktop 补丁更新：AHK 主进程现在每分钟检查 `OpenAI.Codex` 的 Store 包版本；只有“状态版本相同且当前版本的 stable/no-lock 两个 exe/ASAR 都存在”才跳过。首次运行、版本变化或状态领先于产物时都会构建，且构建返回 0 后仍要验证四个文件才写入 `last_built_version` 和提示。
- 已完成：已停用旧的 `CodexHistoryAllProvidersPatchWatcher` 用户 Run 自启动项；现在只保留 `D:\Workspace\AHK\main.ahk` 中的一套 watcher，历史旧补丁目录和备份未删除。
- 已完成：`main.ahk /Validate` 现在是无副作用的解析入口，不会再意外启动第二套 AHK 定时器；现场已收敛为一个 AHK 主进程。
- 已完成：已适配 Store `OpenAI.Codex 26.721.4979.0` 的新压缩变量名；stable/no-lock 副本均已真实重建，stable 恢复当前 model/provider、turn 回放和 provider 参数转发，no-lock 已关闭单实例锁。该版本的全 provider 历史锚点已由上游改为 `modelProviders:[]`，补丁器会验证并保留这一正确语义。
- 已验证：`tests/codex_desktop_patch_watcher_tests.ahk`、`main.ahk /Validate` 与补丁器 Node 测试 3/3 通过；重解包两个新 ASAR 后，stable/no-lock 的关键锚点均符合预期。
- 现状：已定位并修复 Codex 第 4 套 `Right Code` 预设被识别/刷新回第 3 套 `何意味` 的根因：`profiles.ini` 里两者的 `template_provider_base_url` 曾同时写成 `https://ai.websee.top`，共享模板开启后会按这个错误真源重建第 4 套配置。
- 已完成：`right_code.template_provider_base_url` 已改为 `https://www.right.codes/codex/v1`；本机被忽略的 `secrets/right_code/config.toml` 也已同步改到该地址，避免下次切换目标预设时继续复制旧地址。
- 已完成：`tests/codex_profile_switcher_tests.ahk` 已补断言，要求共享模板同步后 `Right Code` 使用 `https://www.right.codes/codex/v1`，且生成后的 config 不再与 `何意味` 完全相同。
- 现状：ChatGPT 托盘菜单已按最新反馈改为 `ChatGPT 浮窗 > 关闭浮窗 > 各桌面浮窗`。用户点某个桌面浮窗项会直接关闭它，不再进入第三层“关闭/不关闭”确认菜单。
- 已完成：`ChatGPT 浮窗 >` 现在保留三个核心入口：`关闭浮窗`、`外链用 Firefox 打开：开/关`、`浮窗配置`。外链开关会写回 `config/chatgpt_chrome_window.ini` 的 `[external_links] enabled`，关闭时停止路由进程，开启时立即尝试启动路由。
- 已完成：“运行中”判断标准仍是 HWND 是否仍然可用，也就是窗口/进程还活着；不要求窗口在前台，也不要求当前可见。窗口不可用时显示“未运行”，但仍可通过“关闭浮窗”清理该桌面的陈旧状态。
- 已验证：本轮菜单修正后，`tests/chatgpt_chrome_window_tests.ahk` 94 项通过；旧的 `浮窗列表`、`BuildWindowListMenu`、`BuildWindowActionMenu`、`RefreshWindowListMenu` 等菜单结构文本/函数名已无残留。
- 现状：已补上 2026-07-01 漏掉的“按虚拟桌面隔离 ChatGPT 浮窗”能力。现在 `Alt+Space` 只解析当前虚拟桌面的浮窗状态；当前桌面没有浮窗时会新建属于该桌面的浮窗，不会再把其他虚拟桌面的浮窗抢过来当成当前实例。
- 已完成：`logs/chatgpt_chrome_window_state.ini` 的状态结构已从单 `[window]` 扩展为按桌面保存的 `[desktop:<id>]`；旧 `[window]` 仍作为兼容来源，仅在状态文件还没有任何 `[desktop:*]` section 时读取。
- 已完成：`ChatGPT 浮窗 >` 托盘菜单新增“关闭指定桌面浮窗...”，点击时会动态读取状态文件并列出 `当前桌面 <短ID>：<标题>` 或 `桌面 <短ID>：<标题>`；同时“关闭当前桌面浮窗”和“关闭全部浮窗”都改为按桌面状态执行。
- 已完成：取消了昨天留下的全局单实例剪枝调用；之前的 `ChatGptChromePruneDuplicateManagedWindows()` 会把多个候选窗口收敛成一个，这与“每个虚拟桌面一个浮窗”冲突。现在多桌面多浮窗是预期行为。
- 已验证：本机注册表当前虚拟桌面 ID 可读，探针值为 `3b6b114708c15d43a81c7a7073cc724c`；实现优先读 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops -> CurrentVirtualDesktop`，失败时回退 `default`，不恢复慢的 PowerShell/C# helper。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk` 已增至 91 项并通过；`tests/hotkey_help_tests.ahk` 10 项通过；`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过；`tests/sandbox_bridge_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、`main.ahk /Validate`、`node --check tools/chatgpt_external_link_router.mjs` 均退出码 0。
- 现状：Chrome-CDP 日常入口已落地到 D 盘独立数据目录 `D:\AppData\Chrome\Chrome-CDP\User Data`；桌面和开始菜单均已创建 `Chrome CDP 日常版.lnk`，启动参数固定包含 `--user-data-dir`、`--profile-directory="Default"`、`--remote-debugging-port=9222`、`--remote-debugging-address=127.0.0.1`、`--no-first-run`、`--no-default-browser-check`。
- 已完成：Codex 全局 MCP 已新增 `chrome-devtools`，配置为 `npx -y chrome-devtools-mcp@latest --browser-url=http://127.0.0.1:9222`；`codex mcp list` 已能看到该 server 处于 enabled 状态。注意：当前已经打开的 Codex 线程不一定立刻暴露新 MCP tools，通常需要新线程/重启后才会进入当前工具面。
- 已完成：`config/chatgpt_chrome_window.ini` 已改为使用 D 盘 Chrome-CDP User Data，并默认启用 9222 CDP 端口与外链转 Firefox 开关；`ChatGptChromeBuildLaunchCommand()` 现在会把这些 Chrome-CDP 参数写入浮窗启动命令。
- 已完成：AHK 托盘菜单已从一级平铺整理为 `查看热键`、`ChatGPT 浮窗 >`、`Codex 配置 >`、标准菜单项；`ChatGPT 浮窗` 子菜单包含显示/切换、关闭当前、关闭全部候选、重置位置/大小、启动/停止外链转 Firefox。
- 已完成：新增 `tools/chatgpt_external_link_router.mjs`。该脚本通过 CDP browser websocket 监听新 page target，只处理 opener 是 ChatGPT target 的 http/https 外链；转发到 Firefox 后关闭 Chrome 里的新 target，避免 app 模式下链接开到看不见的 Chrome 窗口/标签。
- 已验证：`http://127.0.0.1:9222/json/version` 已返回 `Chrome/149.0.7827.200` 与 browser websocket；`npx -y chrome-devtools-mcp@latest --help` 可正常显示 `--browserUrl/--autoConnect` 等参数；外链路由脚本已做 2 秒真实连接冒烟，能连上 Chrome CDP 并识别 Firefox 路径 `C:\Program Files\Mozilla Firefox\firefox.exe`。
- 已验证：本轮完整回归包括 `tests/chatgpt_chrome_window_tests.ahk` 78 项通过、`tests/hotkey_help_tests.ahk` 10 项通过、`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过、`tests/sandbox_bridge_tests.ahk` 退出码 0、`tests/codex_profile_switcher_tests.ahk` 退出码 0、`main.ahk /Validate` 通过、`node --check tools/chatgpt_external_link_router.mjs` 通过。
- 已定位：用户这次说的“Alt+Space 明显慢半拍”，主因不是 Chrome 本身，而是之前把虚拟桌面 helper 放进了热键主路径。那条链路会同步启动 PowerShell，并用 `Add-Type` 临时编译一段 C# 去调用 Windows 虚拟桌面 COM 接口；对热键小工具来说这条路径太重，确实会拖慢体感。
- 已完成：虚拟桌面 helper 已从 ChatGPT 浮窗模块里完全移除；现在 `ChatGptChromeToggleWindow()` 的常规热路径只走本地窗口判断与 hide/show 召回，不再依赖任何 PowerShell + C# 桥接层。
- 已完成：新增 `ChatGptChromeHandleExistingWindow()` 收口“已有实例”的处理逻辑。现在只要旧 `hwnd` 还活着，就只会被隐藏、恢复、尝试召回，或在失败时明确提示；不会再因为跨桌面接管失败而被 `ForgetManagedWindow()` 清掉，再误判成“没有窗口”去新开第二个实例。
- 已完成：启动防抖时间窗已从 `1200ms` 收紧到 `250ms`。配合“已有实例优先处理”的新主流程，`Alt+Space` 的常规体感已回到更接近上一轮的快速响应，而不是每次都要先等半拍。
- 已完成：新增 `ChatGptChromeGetWindowCloakedReason()` 与 `ChatGptChromeShouldAttemptDesktopRecall()`。前者用 DWM 直接查询窗口 cloak 状态，后者把“什么时候才值得走跨桌面补救”收口成纯逻辑门控；当前跨桌面补救统一回退为“已有实例先收起、再在当前桌面重新展开”的简单逻辑。
- 已完成：修正“误开新实例后尺寸被污染”问题。现在新窗口出现后会先 `WinMove` 到目标矩形，再写回状态文件；不再把 Chrome 自己恢复出来的错误大窗尺寸直接写进 `logs/chatgpt_chrome_window_state.ini`。
- 已验证：本轮回归后，`tests/chatgpt_chrome_window_tests.ahk` 已增至 53 项并通过，其中新增了跨桌面门控测试；`tests/hotkey_help_tests.ahk` 10 项通过，`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过，`tests/sandbox_bridge_tests.ahk` 11 项通过，`tests/codex_profile_switcher_tests.ahk` 通过，`main.ahk /Validate` 也通过。
- 已定位：用户截图里“旧小窗标题是 `Quest 3 快速游戏推荐`、新大窗标题是 `ChatGPT`”这组现象，根因不是默认值再次变大，而是旧窗标题已经变成会话名，未命中早期那条“标题含 `ChatGPT` 才算受管窗口”的脆弱识别规则，导致脚本误判为“当前没有浮窗”并再次 `Run --app=...`。
- 已完成：ChatGPT 浮窗的单实例识别现已不再只依赖标题含 `ChatGPT`；新逻辑会综合“Chrome 顶层窗口 + topmost 样式 + app 标题形态 + 历史矩形接近度”挑选候选，并额外偏向“具体会话名窗口”而不是泛化首页标题。
- 已完成：ChatGPT 浮窗现在按“永远只允许一个实例存在”执行。只要还能找到任何一个受管候选，脚本就不会再次 `Run --app=...`；若现场已经遗留多个候选，则会自动收敛到一个首选实例，其余实例优先尝试关闭，关闭失败再隐藏兜底。
- 已完成：ChatGPT 浮窗当前已不再依赖 Windows 虚拟桌面 COM 桥接能力；跨桌面场景只做“单实例不误开 + hide/show 召回”，不再尝试通过额外 helper 搬运窗口到当前桌面。
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
- 已验证：当前仓库真实状态文件 [logs/chatgpt_chrome_window_state.ini](/D:/Workspace/AHK/logs/chatgpt_chrome_window_state.ini) 里记录的最近窗口尺寸为 `735x948`，而静态默认配置 [config/chatgpt_chrome_window.ini](/D:/Workspace/AHK/config/chatgpt_chrome_window.ini) 仍是 `540x760`；这证明用户看到的“大窗”并不是默认值变大，而是误开实例后的窗口尺寸曾被写回状态文件。
- 现状：Codex 预设现已从“`custom / right_code` 历史命名”收口到统一的 `OpenAI` provider 命名；`海豹云-天才程序员`、`何意味`、`Right Code` 都会在共享模板回写时生成 `model_provider = "OpenAI"` 与 `[model_providers.OpenAI]`，`OpenAI Official` 仍保持“顶层不显式写 `model_provider`”的保守策略。
- 已完成：`config/codex_profiles/profiles.ini`、`settings.ini`、本机 secrets 与当前 live `~/.codex/config.toml` 已统一补成四套预设：`openai_official / haibao / heyiwei / right_code`；共享模板成员顺序与托盘菜单顺序也已同步改为 `OpenAI Official -> 海豹云-天才程序员 -> 何意味 -> Right Code`。
- 已完成：按用户 2026-06-23 的更正，现已只让海豹云使用 IP `http://42.192.94.176:5002`；`何意味` 与 `Right Code` 改回 URL `https://ai.websee.top`；`OpenAI Official` 恢复为原先的 URL 方案 `https://code.rpgame.net`，不再误写成统一 IP。
- 现状：已新增 AHK 托盘菜单能力：`查看热键` 使用显式注册表展示当前加载热键，`Codex 预设` 支持从托盘或 `Ctrl+Alt+F12` 弹出菜单切换多套 Codex 配置；沙盒中转 `Ctrl+Alt+C` 已升级为“Explorer 原生选中读取优先、剪贴板兜底”，并额外兼容“右侧预览窗格/第三方预览处理器抢焦点”的情况。
- 已完成：Codex 预设切换现在会在真正覆盖目标预设前，先把当前 live `auth.json + config.toml` 整文件回写到来源预设；即使 live `config.toml` 已因用户运行时手改而不再字节匹配任何预设，也会继续回退到 `state.ini` 中的 `last_switch` 作为来源预设兜底，避免“插件/MCP/provider 改了却在下次切回时被旧预设整文件覆盖”。
- 已完成：新增 `config/codex_profiles/settings.ini` 与四套预设的 provider 模板元数据。开启 `shared_template.enabled=1` 后，任意一套成员预设的 live `config.toml` 都会被视为“公共模板来源”，同步追平到 `openai_official / haibao / heyiwei / right_code` 四套预设，仅保留各自 provider 差异。
- 已完成：已核对 `OpenAI Official` 与海豹云/当前 live 的结构差异；确认 MCP 变少的根因就是 `openai_official/config.toml` 确实缺少 `context7 / github / figma / stitch` 等 MCP 定义，且插件清单也比当前 live 更少。
- 已完成：四套预设现已按“plain MCP 为真源”统一补齐 `context7 / github / cloudflare-api`；`Right Code` 与 `何意味` 均朝海豹云结构对齐，仅保留 provider 差异。
- 已完成：为避免和已迁移到全局的 skills / MCP 重复，`github@openai-curated`、`cloudflare@openai-curated` 已从三套预设里改为关闭；`OpenAI Official` 额外关闭了用户点名的 `canva / figma / stripe / vercel` plugin。
- 已完成：新增 Codex 预设清单 `config/codex_profiles/profiles.ini`，当前包含 `OpenAI Official`、`海豹云-天才程序员`、`何意味`、`Right Code` 四套；真实 `auth.json/config.toml` 放入已忽略的 `secrets` 目录，不进入 Git。
- 已完成：切换流程会按需校验 JSON/TOML、切换前备份 live 配置、写入后做字节级比对，成功/失败只用鼠标附近 ToolTip 提示。
- 已完成：`modules/sandbox_bridge.ahk` 新增 Shell COM 读取路径：当前前台位于资源管理器主窗口或其子窗口时，优先通过 `Shell.Application.Windows -> Document.SelectedItems() -> FolderItem.Path` 直接读取选中项；原 `Send("^c") + ClipWait + A_Clipboard` 方案保留为 fallback，并继续写详细日志。
- 已完成：修复 Shell COM 集合枚举 bug。此前日志连续报 `This value of type "Integer" has no property named "HWND"`，根因是把 `ShellWindows` 的迭代结果误当成窗口对象；现已改为 `Count + Item(i)` 方式读取。
- 已完成：新增“根祖先窗口句柄”匹配逻辑。当前焦点若落在预览窗格、列表子控件或第三方预览处理器上，会先通过 `GetAncestor(..., GA_ROOT)` 回到最外层 Explorer 主窗口，再与 `ShellWindows` 匹配。
- 已完成：新增 `tests/sandbox_bridge_tests.ahk`，覆盖 Explorer 窗口匹配、候选路径去重、缺失路径过滤、匹配窗口选中项解析，以及 `Count + Item(i)` 形式的 COM 集合访问。
- 已验证：`tests/hotkey_help_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、`tests/markdown_reference_link_inliner_tests.ahk` 全部通过；其中热键帮助测试已覆盖托盘菜单初始化路径，`main.ahk /Validate` 也已通过，且相关测试入口已显式 include `utils.ahk` 消除 `Toast` 静态警告；Python TOML 校验已兼容 Windows 常见 UTF-8 BOM。
- 已验证：本轮 `OpenAI` 命名收口后，`tests\codex_profile_switcher_tests.ahk`、`main.ahk /Validate`、四套本机预设 `haibao / openai_official / right_code / heyiwei` 的 `validate_codex_profile.py`，以及当前 live `%USERPROFILE%\.codex\auth.json + config.toml` 校验均已通过。
- 已验证：本轮“只有海豹云使用 `http://42.192.94.176:5002`，`何意味 / Right Code` 使用 `https://ai.websee.top`，`OpenAI Official` 保持 `https://code.rpgame.net`”的修正已通过共享模板回写测试与四套本机配置校验，不会再把所有预设统一刷成同一个 IP。
- 已验证：`logs\sandbox_bridge.log` 已明确证明旧问题断在 `ClipWait(0.8)` 超时，而不是后续 `FileExist()`；用户补充“右侧预览窗格打开就不行、关掉就行”后，又结合 Microsoft Learn 的 Preview Handler 文档确认：预览窗格本就是宿主 + 预览处理器协作的子窗口区域，这条线索与“焦点落到子窗口/第三方预览组件”高度一致。
- 已验证：用 PowerShell + Shell COM 对真实 Explorer 窗口做了现场探针，已能读到当前窗口句柄 `393424`、文件夹 `C:\Users\ZJHSteven\Downloads\__AHK_Transit__` 与选中项 `C:\Users\ZJHSteven\Downloads\__AHK_Transit__\张家赫.pptx`，说明修正后的主路径在这台机器上可用。
- 已验证：`tests\sandbox_bridge_tests.ahk`、`tests\hotkey_help_tests.ahk`、`tests\codex_profile_switcher_tests.ahk`、`tests\markdown_reference_link_inliner_tests.ahk` 与 `main.ahk /Validate` 全部通过。
- 已验证：本轮已补“auth refresh 后仍能识别当前预设”、“切换前先回写来源整文件”与“config 已漂移时仍可依赖 last_switch 回写来源整文件”三条自动化用例；落地后需要再次执行 `tests\codex_profile_switcher_tests.ahk` 与 `main.ahk /Validate` 做回归确认。
- 已验证：Cloudflare 插件缓存当前真实结构是 `skills + .mcp.json`，其中 `.mcp.json` 暴露的就是 `cloudflare-api -> https://mcp.cloudflare.com/mcp`；GitHub 插件缓存真实结构则是 `skills + .app.json`，说明把 `cloudflare/github` plugin 与 plain MCP 同时打开，确实会形成重复入口。
- 已完成：按用户 2026-06-29 的更正，第三套预设的用户可见中文名与内部 id 已统一收口为“何意味 / `heyiwei`”；对应 secrets 路径、模板成员列表、测试夹具和验证说明均已同步，避免后续看配置和日志时继续混淆。
- 下一步：执行一轮 Codex 预设专项回归：确认 `何意味` 能在托盘菜单里被识别，确认切到海豹云后 live `config.toml` 仅海豹云使用 `http://42.192.94.176:5002`，而切到 `何意味 / RC / OpenAI Official` 后会分别恢复各自 URL，再回头继续 Explorer 预览窗格的手工复现。
- 下一步：如果用户后续确认还要保留真正的多标签页工作流，再把 `config/chatgpt_chrome_window.ini -> window_mode` 从 `app` 切回 `window`，或补一套“app / window 双实例”切换策略。
- 下一步：让用户现场重点复测两条：1) 同桌面下 `Alt+Space` 是否恢复到立即收起/唤起；2) 窗口留在桌面1、切到桌面2后再按 `Alt+Space` 时，是否还会误开第二个实例。若当前记忆尺寸仍表现为大窗，可先从托盘执行“重置 ChatGPT 浮窗位置/大小”，把已污染的 `735x948` 状态清回默认小窗。

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
- 决策F.2：只有海豹云使用 `http://42.192.94.176:5002`；`何意味` 使用 `https://ai.websee.top`；`Right Code` 使用 `https://www.right.codes/codex/v1`；`OpenAI Official` 继续保持 `https://code.rpgame.net`。
  原因：`profiles.ini` 是共享模板重建 provider block 的真源；如果第 3、第 4 套 URL 写成一样，刷新时就会把 `Right Code` 重新覆盖成 `何意味`，甚至因为 auth/config 完全相同导致菜单按顺序误识别为第 3 套。
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
- 决策P：当前版本明确按“严格单实例”收口，而不是“先允许多窗、再随机接管一个”。
  原因：在没有设计好多窗口交互模型之前，允许出现第二个但又不能保证每个窗口都受快捷键掌控，只会制造不可预测状态；这比暂时不支持多窗更差。
- 决策Q：跨虚拟桌面优先做“同一实例跟随/搬运”，而不是“当前桌面看不见就新开一份”。
  原因：用户已经明确确认这不是多窗口设计需求，而是当前桌面可见性误导了实例判断；因此修复方向应该是保持单实例并移动它，而不是继续扩展多实例分支。
- 决策R：Chrome-CDP 日常入口使用 D 盘独立 User Data + 固定 `127.0.0.1:9222`，不把原始 Chrome 默认数据目录直接拿来开远程调试。
  原因：Chrome 136 之后默认数据目录受远程调试限制；独立目录既符合安全边界，也方便 Codex MCP、AHK 和普通 CDP 脚本稳定连接。
- 决策S：Chrome DevTools MCP 采用 `--browser-url=http://127.0.0.1:9222`，暂不采用 `--autoConnect` 作为主路径。
  原因：`--autoConnect` 更适合临时授权接管现有 Chrome；本项目要的是日常长期可预测的后台调试入口，固定本机端口更适合脚本化。
- 决策T：ChatGPT 外链转 Firefox 通过独立 CDP Node 脚本实现，而不是写成 Chrome 全局规则。
  原因：同一个 Chrome-CDP profile 里可能存在普通浏览窗口；只有 opener 是 ChatGPT target 的新页面才应该被转发，避免误关用户自己打开的普通 Chrome 页面。
- 决策U：ChatGPT 浮窗改为“每个虚拟桌面一份状态”，而不是继续维持全局单实例。
  原因：用户明确要的是虚拟桌面之间互相隔离；全局单实例会导致一个桌面的浮窗被另一个桌面抢用，也无法从菜单选择关闭某个桌面的浮窗。
- 决策V：当前虚拟桌面 ID 优先从 Explorer 注册表读取，失败时回退 `default`。
  原因：注册表读取足够轻量，能避开之前 PowerShell/C# helper 导致的热键慢半拍；回退值保证单桌面/读取失败时仍能按旧逻辑运行。
- 决策W：ChatGPT 托盘菜单只保留“浮窗列表”，不再暴露显示/切换、关闭当前、关闭全部等快捷按钮。
  原因：显示/切换已有 `Alt+Space`，关闭动作应围绕具体浮窗做二次确认；把所有动作平铺只会让托盘菜单越来越长。

## 常见坑 / 复现方法
- 坑1：切换 Codex 配置后，已经打开的 Codex 终端通常不会自动重新读取配置；需要关闭并重新打开终端。
- 坑2：`OpenAI Official` 和 `Right Code` 初始只在 `profiles.ini` 里占位；没有补齐对应 `secrets/<profile_id>/auth.json` 与 `config.toml` 前，菜单会显示但禁用。
- 坑3：如果 live `.codex` 被外部手动改到不匹配任何预设，托盘菜单不会误报“当前”；下次切换仍会先备份这个未知状态，再写入目标预设。
- 坑3.1：虽然托盘菜单不会把“已经漂移的 live”误标成当前预设，但切换前的同步流程现在会依赖 `state.ini -> last_switch` 兜底，把这份 live 整文件回写到最近一次成功切入的来源预设；这是为了保住用户运行期手改的配置，不是 UI 当前态判定。
- 坑3.2：开启 `settings.ini -> shared_template.enabled=1` 后，来源预设的 live `config.toml` 会自动扩散到模板组内其他成员预设；因此如果只是临时实验某个 provider 的私有配置，应先关掉该开关，避免把实验配置同步给另外三套预设。
- 坑3.3：现在 `haibao / right_code / heyiwei` 的顶层 `model_provider` 都会被强制写成 `OpenAI`；如果只手改某份 secrets 或 live 文件里的旧 `custom/right_code` 字样，不同步更新 `profiles.ini`，下一次切换仍会被共享模板改回。
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
- 坑13：安装 `chrome-devtools` MCP 后，`codex mcp list` 能证明配置已落盘，但当前已经运行的 Codex 线程不一定马上出现新 MCP tools；需要新开线程或重启 Codex 后再看当前工具面。
- 坑14：外链转 Firefox 依赖 Chrome-CDP 端口已打开；如果 `http://127.0.0.1:9222/json/version` 连接被拒绝，先从桌面或开始菜单启动 `Chrome CDP 日常版`，不要从旧的 Chrome 原始快捷方式启动。
- 坑15：`tools/chatgpt_external_link_router.mjs` 只转发 opener 是 ChatGPT target 的 http/https 外链；如果某个链接不是由 ChatGPT 页面打开，或 Chrome 没有提供 openerId，它不会被转发。这是防误伤设计，不是脚本漏处理。
- 坑16：如果某个桌面的浮窗没有出现在“关闭指定桌面浮窗...”菜单里，先确认它至少被当前脚本启动/识别并写入过 `[desktop:<id>]` 状态；手动从 Chrome 里随便开的窗口不会自动成为受管浮窗。
- 坑17：桌面名称/编号仍未接入 Windows 内部虚拟桌面库，菜单目前显示短桌面 ID + 窗口标题。这是为了保持热键路径轻量；若以后必须显示桌面名称，再单独评估更重的虚拟桌面库。
- 坑18：`浮窗列表` 是一个真正的托盘子菜单，但它的内容来自 AHK 状态文件；如果用户手动绕过 AHK 在 Chrome 里开窗口，它不会自动出现在这里。只有被 AHK 启动/识别并写入 `[desktop:<id>]` 的浮窗才会列出。
