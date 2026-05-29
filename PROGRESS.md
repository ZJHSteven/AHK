# 项目状态快照（保持短小：建议 <= 200~400 行）

## 当前结论（必须最新）
- 现状：已新增 AHK 托盘菜单能力：`查看热键` 使用显式注册表展示当前加载热键，`Codex 预设` 支持从托盘或 `Ctrl+Alt+F12` 弹出菜单切换多套 Codex 配置；沙盒中转 `Ctrl+Alt+C` 已升级为“Explorer 原生选中读取优先、剪贴板兜底”，并额外兼容“右侧预览窗格/第三方预览处理器抢焦点”的情况。
- 已完成：Codex 预设切换现在会在真正覆盖目标预设前，先把当前 live `auth.json` 回写到来源预设；即使 `OpenAI Official` 的 token 因自动 refresh 导致 auth 文件已与 secrets 不同，只要 `config.toml` 仍匹配，脚本仍能识别并同步最新 token，避免切回旧 auth。
- 已完成：已核对 `OpenAI Official` 与海豹云/当前 live 的结构差异；确认 MCP 变少的根因就是 `openai_official/config.toml` 确实缺少 `context7 / github / figma / stitch` 等 MCP 定义，且插件清单也比当前 live 更少。
- 已完成：新增 Codex 预设清单 `config/codex_profiles/profiles.ini`，第一版包含 `海豹云-天才程序员`、`OpenAI Official`、`Right Code` 三套；真实 `auth.json/config.toml` 放入已忽略的 `secrets` 目录，不进入 Git。
- 已完成：切换流程会按需校验 JSON/TOML、切换前备份 live 配置、写入后做字节级比对，成功/失败只用鼠标附近 ToolTip 提示。
- 已完成：`modules/sandbox_bridge.ahk` 新增 Shell COM 读取路径：当前前台位于资源管理器主窗口或其子窗口时，优先通过 `Shell.Application.Windows -> Document.SelectedItems() -> FolderItem.Path` 直接读取选中项；原 `Send("^c") + ClipWait + A_Clipboard` 方案保留为 fallback，并继续写详细日志。
- 已完成：修复 Shell COM 集合枚举 bug。此前日志连续报 `This value of type "Integer" has no property named "HWND"`，根因是把 `ShellWindows` 的迭代结果误当成窗口对象；现已改为 `Count + Item(i)` 方式读取。
- 已完成：新增“根祖先窗口句柄”匹配逻辑。当前焦点若落在预览窗格、列表子控件或第三方预览处理器上，会先通过 `GetAncestor(..., GA_ROOT)` 回到最外层 Explorer 主窗口，再与 `ShellWindows` 匹配。
- 已完成：新增 `tests/sandbox_bridge_tests.ahk`，覆盖 Explorer 窗口匹配、候选路径去重、缺失路径过滤、匹配窗口选中项解析，以及 `Count + Item(i)` 形式的 COM 集合访问。
- 已验证：`tests/hotkey_help_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、`tests/markdown_reference_link_inliner_tests.ahk` 全部通过；其中热键帮助测试已覆盖托盘菜单初始化路径，`main.ahk /Validate` 也已通过，且相关测试入口已显式 include `utils.ahk` 消除 `Toast` 静态警告；Python TOML 校验已兼容 Windows 常见 UTF-8 BOM。
- 已验证：`logs\sandbox_bridge.log` 已明确证明旧问题断在 `ClipWait(0.8)` 超时，而不是后续 `FileExist()`；用户补充“右侧预览窗格打开就不行、关掉就行”后，又结合 Microsoft Learn 的 Preview Handler 文档确认：预览窗格本就是宿主 + 预览处理器协作的子窗口区域，这条线索与“焦点落到子窗口/第三方预览组件”高度一致。
- 已验证：用 PowerShell + Shell COM 对真实 Explorer 窗口做了现场探针，已能读到当前窗口句柄 `393424`、文件夹 `C:\Users\ZJHSteven\Downloads\__AHK_Transit__` 与选中项 `C:\Users\ZJHSteven\Downloads\__AHK_Transit__\张家赫.pptx`，说明修正后的主路径在这台机器上可用。
- 已验证：`tests\sandbox_bridge_tests.ahk`、`tests\hotkey_help_tests.ahk`、`tests\codex_profile_switcher_tests.ahk`、`tests\markdown_reference_link_inliner_tests.ahk` 与 `main.ahk /Validate` 全部通过。
- 已验证：本轮已补“auth refresh 后仍能识别当前预设”与“切换前先回写来源 auth”两条自动化用例；落地后需要再次执行 `tests\codex_profile_switcher_tests.ahk` 与 `main.ahk /Validate` 做回归确认。
- 下一步：Reload AHK 后，分别在“预览窗格关闭”和“预览窗格打开”两种状态下，对同一文件各试一次 `Ctrl+Alt+C`；若仍异常，优先读取 `logs\sandbox_bridge.log` 中新增的 `match_hwnd / match_exe / capture explorer:` 日志，再判断是根窗口识别失败，还是 `SelectedItems()` 为空。

## 关键决策与理由（防止“吃书”）
- 决策A：热键帮助采用显式注册表，不从注释自动解析。
  原因：注释格式适合人读，不适合当稳定数据源；显式注册表能保证展示内容可控，尤其适合后续给新人维护。
- 决策B：Codex 预设切换采用整文件替换，而不是只改局部字段。
  原因：`auth.json` 与 `config.toml` 的真实结构可能随 Codex 变化；整文件预设最直观，切换后也能直接字节比对确认成功。
- 决策C：真实预设文件不提交，只提交清单、代码和说明。
  原因：`auth.json` 可能包含 API Key / OAuth token，进入 Git 历史后很难彻底清理。
- 决策D：Codex 预设切换默认只自动回写来源预设的 `auth.json`，不自动回写 `config.toml`。
  原因：`auth` 属于会被平台自动刷新的运行态凭据，应该始终跟随 live 追最新；`config.toml` 更像人工维护的预设定义，自动回写容易把临时漂移或缺失的 MCP 配置反向固化。
- 决策E：资源管理器场景优先直接读取 Explorer 选中项，不再把“真实路径获取”完全绑定到剪贴板复制链路。
  原因：本次现场日志多次证明前台已是 `explorer.exe`、`Ctrl+C` 已发送，但 `ClipWait` 仍超时；继续只调等待时间没有意义，应该改为更贴近 Explorer 内部状态的读取方式。
- 决策F：Explorer 匹配以“根祖先窗口”而不是“瞬时焦点子窗口”为准。
  原因：右侧预览窗格、文件列表控件、第三方 Preview Handler 都可能拿走前台焦点；若只认瞬时子窗口，脚本会错误地认为自己“不在资源管理器主窗口”。

## 常见坑 / 复现方法
- 坑1：切换 Codex 配置后，已经打开的 Codex 终端通常不会自动重新读取配置；需要关闭并重新打开终端。
- 坑2：`OpenAI Official` 和 `Right Code` 初始只在 `profiles.ini` 里占位；没有补齐对应 `secrets/<profile_id>/auth.json` 与 `config.toml` 前，菜单会显示但禁用。
- 坑3：如果 live `.codex` 被外部手动改到不匹配任何预设，托盘菜单不会误报“当前”；下次切换仍会先备份这个未知状态，再写入目标预设。
- 坑4：`OpenAI Official` 的 `auth.json` 不是静态 API Key 文件，还会包含 `auth_mode / last_refresh / tokens`；如果切换器只做“预设覆盖 live”，不做“离开前回写来源 auth”，下次切回就会被旧 refresh token 覆盖。
- 坑5：沙盒中转 `Ctrl+Alt+C` 若在资源管理器已选中文件但仍提示未拿到路径，先看 `logs/sandbox_bridge.log`，重点检查活动窗口、剪贴板文本长度、候选路径和 `FileExist()` 结果。
- 坑6：如果是资源管理器窗口，最新日志里应优先关注 `capture explorer:` 分支；只有当这里明确返回 0 项时，脚本才会退回到旧的 `capture clipboard:` 分支。
- 坑7：如果右侧预览窗格启用了第三方预览器（例如 WPS 提供的 Office 预览），问题不一定表现为“窗口不是 Explorer”；更常见的是焦点落到 Explorer 内部的预览子窗口，导致旧的 `Ctrl+C` 抓取链路更容易失效。因此这类问题要优先看 `match_hwnd` 和 `match_exe`，不要只盯 `hwnd/exe/title` 的第一层日志。
