# ExecPlan

## 2026-08-13 Codex Desktop watcher 发布协议路由 Stage 5

### 当前目标

- watcher 从 Stage 4 发布契约升级到当前已真实运行的 Stage 5。
- 就绪判定必须检查 `protocol-observer-stage5`、`stage5-manifest.json`、无密钥路由配置、
  Shim/real CLI/helper，以及何意味 Sol、何意味 Terra、DeepSeek Flash 三个已验收模型。
- Store 更新时只在 Stage 5 构建、协议契约和必要文件全部通过后发布 `runtime/state.json`；
  失败继续保留上一版 Stable，并沿用 30 分钟退避。
- 不由自动化关闭、替换或 Reload 当前管理员 AHK；代码完成后由用户手动 Reload。

### 验收计划

1. [ ] 将就绪函数、构建函数、命令、日志和提示统一从 Stage 4 升到 Stage 5。
2. [ ] 单元测试覆盖空目录、缺文件、错误 architecture、错误版本、缺模型和正确 Stage 5。
3. [ ] 运行 watcher 单元测试、真实 AHK → PowerShell Stage 5 集成测试和 `main.ahk /Validate`。
4. [ ] 只读确认当前 Desktop 仍为 Stage 5 进程链，且测试没有启动或关闭 Desktop/AHK 常驻实例。
5. [ ] 用户手动 Reload 管理员 AHK 后，检查日志出现新的 watcher 启动记录且不触发 Stage 4 回退。

## 2026-08-13 Codex Desktop watcher 发布协议路由 Stage 4

### 当前目标

- watcher 从纯透明 `stage1` 升级为构建并发布 `stage4`，保留脱敏协议观测，并启用虚拟模型目录与双向模型转译。
- 就绪判定必须检查 `protocol-observer-stage4` manifest、无密钥路由配置、Shim/real CLI/helper，以及已验收的何意味 Sol、何意味 Terra、DeepSeek Flash 三个模型。
- Store 更新时先在 staging 完成透明性、模型目录与路由契约测试，成功后才切换 `runtime\state.json` 和 Stable；失败继续保留上一版可用 Stable。
- 当前已加载的管理员 AHK 实例不在本轮强制重启，避免再次触发权限/单实例弹窗；代码将在用户下次正常重启 AHK 后生效。

### 验收计划

1. [x] 将就绪函数、构建命令、日志和提示从 Stage 1 契约升级到 Stage 4。
2. [x] 更新单元夹具，覆盖缺文件、错误 architecture、路由配置和三个已验收模型的完整 Stage 4。
3. [x] watcher 单元测试、真实 AHK → PowerShell 集成测试及补丁器完整回归通过。
4. [x] 已验收 Stage 4 已发布为 Stable，当前 Codex 未重启；用户下次从桌面 Stable 进入后做真实中转请求验收。

## 2026-08-12 Codex Desktop watcher 迁移到透明 Shim Stage 1

### 当前目标

- 停止把 ASAR Stable/NoLock 两套产物作为 watcher 完成条件。
- watcher 改为调用 `Build-CodexDesktopStage1.ps1`，只发布“整树 Clone + codex-real.exe + 零改写 stdio shim”。
- 只有 Stage 1 manifest、ChatGPT.exe、原版 app.asar、shim、real CLI 和 helper 全部存在时才写入成功版本。
- 构建 stdout/stderr 必须完整写入日志；失败时保留上一版可用产物并退避，不再只记录 exit code。

### 验收计划

1. [x] 重写产物就绪判断并补空目录、部分文件、错误 manifest、完整 Stage 1 四类边界。
2. [x] 重写构建命令，只调用 Stage 1 构建器和 Stable-only 启动器，不再构建 NoLock。
3. [x] 使用临时日志验证 stdout/stderr 捕获，状态 INI 只保留单一 `[state]`。
4. [x] watcher 专项测试与真实 AHK -> PowerShell 集成冒烟通过；`main.ahk /Validate` 因现有管理员单实例早于脚本参数处理而弹出权限提示，已停止用非管理员进程重试。
5. [ ] 在用户允许的维护窗口，以管理员权限重启现有 AHK 常驻实例，使新 watcher 代码真正加载；不影响当前 Codex Desktop 进程。

## 2026-07-30 Codex Desktop watcher 换行误判收口

### 已确认根因

- `Set-Content` 写出的 Store 版本末尾带 CRLF，而 AHK `Trim()` 默认不移除回车换行。
- 带换行的版本被用于拼接 runtime 目录，导致 stable/no-lock 已成功构建后仍被误判为缺失。
- 原测试使用正则结尾锚点，没有显式拒绝 CR/LF，因此未覆盖该真实边界。

### 执行计划

1. 版号读取显式移除空格、Tab、CR 和 LF，并将临时文件写入改为无换行。
2. 测试使用真实读取的版本检查正式 runtime 产物，并显式断言版本中不含 CR/LF。
3. 将 watcher INI 规范化为单一干净版本值，停止错误的周期性强制重建。
4. 在 Store 版本未变化时做一次强制 stable/no-lock 构建验证，随后重启唯一 AHK 实例。
5. 连续观察至少两个轮询周期，要求日志无新增失败、进程数为一、四个产物均存在。

### 执行结果

- 已完成：真实 Store 版本为 `26.721.4979.0`，没有出现两天内的新版本。
- 已完成：版本查询同时使用 `-NoNewline` 与显式 CR/LF 清理；INI 已从 177 行污染内容规范化为单一版本值。
- 已验证：补丁器测试 3/3、AHK watcher 测试、`main.ahk /Validate`、stable/no-lock 强制构建和重新解包静态检查全部通过。
- 已验证：唯一 AHK 实例连续跨过两个一分钟周期，日志无新增失败或重复构建记录，未再触发重复通知。

## 2026-07-28 Codex Desktop watcher 状态与重复检查修复

### 背景

- Store 当前版本已是 `26.721.4979.0`，但本项目 `runtime/state.json` 与实际稳定版 / no-lock 副本仍停留在 `26.707.3748.0`。
- AHK watcher 在 `last_built_version` 为空时直接写入当前版本并返回，没有执行构建；因此首次初始化会产生“状态已最新、产物却不存在”的假成功。
- 旧的 `CodexHistoryAllProvidersPatchWatcher` 仍在用户 Run 自启动项中，与 AHK 的一分钟 watcher 并行运行，造成两套补丁维护机制重叠。

### 执行计划

1. 为 watcher 提取“指定版本的 stable/no-lock 产物是否完整”的纯检查函数，并补最小文件系统边界测试。
2. 将首次初始化改为构建；仅当构建退出成功且两个变体的 exe / ASAR 均存在时才写 `last_built_version`。
3. 当状态版本等于 Store 版本但产物缺失时，自动触发一次强制重建，而不是继续静默跳过。
4. 停用旧 Run 自启动 watcher，保留其文件和历史备份，不删除旧补丁目录。
5. 用 AHK 自动化测试、主脚本语法校验、构建脚本实测和状态文件回读完成验收。

## 2026-07-08 Codex Right Code 预设 URL 真源修复

### 背景
- 用户反馈：通过 `Ctrl+Alt+F12` 切到第 4 套 `Right Code` 后，再打开菜单或刷新配置时，当前配置又像回到了第 3 套 `何意味 / heyiwei`。
- 用户反馈：第 3 套和第 4 套的 `base_url` 变成一样；手动把 `Right Code` 改回正确地址后，刷新又会被改回。
- 现场证据：`shared_template.enabled=1` 开启后，切换器会以 `config/codex_profiles/profiles.ini` 的 `template_provider_base_url` 作为真源重建 provider 块；当前 `heyiwei` 与 `right_code` 都写成 `https://ai.websee.top`。
- 现场证据：备份里存在 `https://www.right.codes/codex/v1`，符合用户描述的 `Right Code` 手动修正地址。

### 执行计划
1. 修正 `profiles.ini` 中 `right_code.template_provider_base_url`，让共享模板重建时使用 `https://www.right.codes/codex/v1`。
2. 同步更新 README、测试夹具和断言，明确 `heyiwei` 与 `right_code` 是两套不同 endpoint。
3. 更新本机被忽略的 `secrets/right_code/config.toml`，避免下一次切换目标预设时仍复制旧地址。
4. 补充或调整测试，覆盖共享模板同步后第 3、第 4 套 URL 不应相同。
5. 运行 AHK 测试、主脚本语法校验和四套预设校验，最后更新 `PROGRESS.md`。

## 2026-07-02 ChatGPT 浮窗托盘菜单改为直接关闭

### 背景
- 用户继续复核托盘交互后指出：上一版 `ChatGPT 浮窗 > 浮窗列表 > 某个桌面浮窗 > 关闭 / 不关闭` 仍然多了一层。
- 更合理的结构是：进入 `ChatGPT 浮窗` 后只看到几个真正有用的管理项；进入 `关闭浮窗` 后直接列出各虚拟桌面浮窗，点击某个浮窗就关闭它。
- “不关闭”没有实际意义，因为不想关闭时用户可以直接移开菜单。

### 目标菜单结构
```text
ChatGPT 浮窗 >
  关闭浮窗 >
    当前桌面 xxxx [运行中]：...
    桌面 yyyy [未运行]：...
  外链用 Firefox 打开：开/关
  浮窗配置
```

### 执行计划
1. 调整 `ChatGptChromeBuildTrayMenu()`，改为挂载 `关闭浮窗`、外链开关、浮窗配置三项。
2. 将关闭浮窗子菜单改为直接绑定 `ChatGptChromeForceCloseDesktopById`，不再创建“关闭 / 不关闭”第三级菜单。
3. 补充/更新测试，覆盖菜单构造、关闭菜单构造、外链开关文本与配置入口。
4. 更新 `PROGRESS.md`，记录最终菜单语义和验证结果。

### 执行结果
- 已完成：`ChatGPT 浮窗 >` 现在显示 `关闭浮窗`、`外链用 Firefox 打开：开/关`、`浮窗配置`。
- 已完成：`关闭浮窗 >` 会直接列出当前/其他桌面的浮窗；点击某个浮窗项会直接关闭该桌面的浮窗。
- 已完成：外链开关会写回 `[external_links] enabled`，并同步启动或停止外链路由进程。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk` 94 项通过，旧的 `浮窗列表` 相关函数名和文案已无残留。

## 2026-07-02 ChatGPT 浮窗托盘菜单收敛为浮窗列表

### 背景
- 用户复核按虚拟桌面隔离浮窗后指出：`关闭指定桌面浮窗...` 现在是点击后弹出的临时菜单，没有像 `ChatGPT 浮窗 >` 那样显示右箭头悬浮子菜单。
- 用户希望托盘交互进一步收敛：不再保留“显示/切换当前浮窗”“关闭当前桌面浮窗”“关闭全部浮窗”等多个按钮；热键已经负责显示/切换，托盘里只保留一个“浮窗列表”。
- 期望结构是：`ChatGPT 浮窗 > 浮窗列表 > 某个桌面浮窗 > 关闭 / 不关闭`，避免菜单越来越长。

### 预期结果
- `ChatGPT 浮窗 >` 下只保留 `浮窗列表`。
- `浮窗列表` 是真正的右箭头子菜单，不再是点击后弹出的临时菜单。
- 每个已记录浮窗显示为一个子菜单项，文本包含当前/非当前桌面、短桌面 ID、运行状态和窗口标题。
- 每个浮窗项下面只有两个操作：
  - `关闭`
  - `不关闭`
- “运行”按进程/窗口句柄是否仍存在判断；只要 HWND 还活着就算运行，不要求窗口在前台。

### 实现步骤
1. 调整 `ChatGptChromeBuildTrayMenu()`，只挂载 `浮窗列表` 子菜单。
2. 新增/调整浮窗列表构造函数，把每个桌面状态生成为二级子菜单。
3. 保留底层关闭当前桌面、关闭全部等函数作为内部能力，但不再暴露到托盘菜单。
4. 补测试覆盖新菜单可构建、运行状态标签和二级子菜单构造。
5. 运行 AHK 相关测试与主脚本语法校验。

### 执行结果
- 已完成：`ChatGPT 浮窗 >` 下已收敛为单一 `浮窗列表` 子菜单。
- 已完成：`浮窗列表` 改为真正的右箭头子菜单；每个浮窗项下面再嵌套 `关闭 / 不关闭`。
- 已完成：浮窗项标签显示当前/非当前桌面、短桌面 ID、运行状态和窗口标题；“运行中”按 HWND 是否仍可用判断，不要求在前台。
- 已完成：底层关闭当前/关闭全部能力仍保留为内部函数，但不再平铺暴露到托盘菜单。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk` 93 项通过，`tests/hotkey_help_tests.ahk` 10 项通过，`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过，`tests/sandbox_bridge_tests.ahk` 11 项通过；`tests/codex_profile_switcher_tests.ahk`、`main.ahk /Validate`、`node --check tools/chatgpt_external_link_router.mjs` 均退出码 0。

## 2026-07-02 ChatGPT 浮窗按虚拟桌面隔离与按桌面关闭

### 背景
- 用户复核 2026-07-01 的实现后指出：托盘菜单虽然被收纳了，但没有真正实现先前讨论的“每个虚拟桌面一个独立 ChatGPT 浮窗，并能从托盘选择关闭某个桌面的浮窗”。
- 现有实现仍是单 `last_hwnd` 状态，只提供“关闭当前浮窗”和“关闭全部浮窗候选”，这不满足“虚拟桌面分隔”的要求。
- 本机注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops` 可读到 `CurrentVirtualDesktop`，因此可以用轻量注册表读取作为当前桌面标识来源，避免恢复之前拖慢热键的 PowerShell/C# helper。

### 预期结果
- `Alt+Space` 在每个虚拟桌面上只管理该桌面自己的 ChatGPT 浮窗：
  - 当前桌面已有浮窗：显示/收起/恢复当前桌面的浮窗；
  - 当前桌面没有浮窗：新建一个属于当前桌面的浮窗；
  - 其他桌面已有浮窗：不抢过来，也不误认为当前桌面已有实例。
- 状态文件支持按桌面保存窗口：
  - 保留旧 `[window]` 作为兼容读取来源；
  - 新增按桌面 key 存储的 `[desktop:<id>]`，分别保存 `last_hwnd/x/y/w/h/window_mode/rect_policy_version`。
- 托盘 `ChatGPT 浮窗 >` 新增按桌面关闭入口：
  - `关闭当前桌面浮窗`
  - `关闭全部浮窗`
  - `关闭指定桌面浮窗 > 桌面 <短ID>：<窗口标题>`
- 测试覆盖：
  - 虚拟桌面 ID 归一化；
  - 按桌面读写状态；
  - 当前桌面只解析自己的窗口；
  - 按桌面关闭菜单可构建；
  - 原有单实例/启动参数/菜单测试继续通过。

### 实现步骤
1. 增加 `ChatGptChromeGetCurrentDesktopId()`，优先读取注册表当前虚拟桌面 GUID，失败时回退到 `default`，保证非虚拟桌面环境也能工作。
2. 将 `ChatGptChromeReadState()` / `ChatGptChromeWriteState()` 扩展为支持 `desktopId` 参数，默认使用当前桌面 ID。
3. 将 `ChatGptChromeResolveManagedWindow()`、保存位置、重置位置、关闭当前浮窗等路径改为当前桌面状态。
4. 新增枚举已保存桌面状态与按桌面关闭函数，构造 `关闭指定桌面浮窗` 子菜单。
5. 补测试并运行完整 AHK 回归。

### 执行结果
- 已完成：状态读写已支持 `[desktop:<id>]`，并保留旧 `[window]` 兼容读取。
- 已完成：`Alt+Space` 现在只管理当前虚拟桌面的浮窗；其他桌面的浮窗不会被抢来当成当前实例。
- 已完成：托盘 `ChatGPT 浮窗 >` 已新增 `关闭指定桌面浮窗...` 动态菜单，并把关闭当前/关闭全部改成按桌面状态执行。
- 已完成：移除热键路径中的全局单实例剪枝调用，允许每个虚拟桌面保留自己的 ChatGPT 浮窗。
- 已验证：当前虚拟桌面 ID 可从注册表读取，本机探针值为 `3b6b114708c15d43a81c7a7073cc724c`。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk` 91 项通过，`tests/hotkey_help_tests.ahk` 10 项通过，`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过；`tests/sandbox_bridge_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、`main.ahk /Validate`、`node --check tools/chatgpt_external_link_router.mjs` 均退出码 0。

## 2026-07-01 Chrome-CDP 日常入口、DevTools MCP 与 ChatGPT 浮窗外链路由

### 背景
- 用户已经确认前置方案：日常开发用 Chrome 走独立 `User Data` 目录，并长期打开本机 CDP 调试端口，方便 Codex、MCP、脚本和 AHK 随时接入。
- 新的 Chrome 数据目录放在 D 盘，避免挤占 C 盘；默认浏览器仍保持 Firefox，不让 Chrome 反复提示设为默认浏览器。
- ChatGPT Chrome 浮窗继续用 AHK 管理，但要把托盘菜单从一级平铺整理成二级菜单，并为后续“外链打开到 Firefox”留出明确入口。

### 预期结果
- 创建稳定目录：`D:\AppData\Chrome\Chrome-CDP\User Data`。
- 创建两个用户入口：
  - 桌面快捷方式：`Chrome CDP 日常版.lnk`。
  - 开始菜单快捷方式：`Chrome CDP 日常版.lnk`。
- 快捷方式启动 Chrome 时固定携带：
  - `--user-data-dir="D:\AppData\Chrome\Chrome-CDP\User Data"`；
  - `--profile-directory="Default"`；
  - `--remote-debugging-port=9222`；
  - `--remote-debugging-address=127.0.0.1`；
  - `--no-first-run`；
  - `--no-default-browser-check`。
- Codex 安装 `chrome-devtools` MCP，优先连接 `http://127.0.0.1:9222`，而不是依赖临时授权式 `autoConnect`。
- AHK 的 ChatGPT 浮窗启动命令同样使用 D 盘 Chrome-CDP 数据目录和 9222 调试端口，确保浮窗与日常 Chrome-CDP 会话一致。
- AHK 托盘菜单整理为：
  - `查看热键`
  - `ChatGPT 浮窗 >`
  - `Codex 配置 >`
  - AHK 标准菜单项
- 外链转 Firefox 先按“可配置、可关闭、最小误伤”的方向落地：只给 ChatGPT 浮窗新增独立开关与脚本入口，不写成全局关闭所有非 ChatGPT Chrome 页面的危险规则。

### 实现步骤
1. 只读确认当前 Chrome 路径、版本、Codex MCP 配置和 AHK 仓库状态；保护用户已有未提交改动。
2. 写入 D 盘 Chrome-CDP 快捷方式，并验证快捷方式目标参数正确。
3. 通过 `codex mcp add` 或等效 `config.toml` 配置安装 `chrome-devtools` MCP，并用本机 `http://127.0.0.1:9222/json/version` 验证 CDP 端口。
4. 更新 `config/chatgpt_chrome_window.ini`，新增 `user_data_dir`、`remote_debugging_port`、`remote_debugging_address`、`no_first_run`、`no_default_browser_check`、`external_links_to_firefox` 等配置。
5. 更新 `modules/chatgpt_chrome_window.ahk`：
   - 读取新增配置；
   - 启动命令带上 Chrome-CDP 数据目录和调试端口；
   - 预留外链路由脚本启动/停止接口；
   - 增加关闭当前浮窗与关闭全部候选浮窗的托盘入口。
6. 更新 `modules/hotkey_help.ahk`，把托盘菜单整理成二级菜单。
7. 补充或更新 `tests/chatgpt_chrome_window_tests.ahk`、`tests/hotkey_help_tests.ahk`，覆盖新增配置解析、启动命令拼装和菜单构建。
8. 运行 AHK 语法校验、相关单元测试、MCP/Chrome 端口验证，最后更新 `PROGRESS.md`。

### 执行结果
- 已完成：`D:\AppData\Chrome\Chrome-CDP\User Data` 已创建，桌面和开始菜单均已生成 `Chrome CDP 日常版.lnk`。
- 已完成：Chrome-CDP 快捷方式已反读确认，目标为 `C:\Program Files\Google\Chrome\Application\chrome.exe`，参数包含 D 盘 User Data、`Default` Profile、`127.0.0.1:9222`、`--no-first-run`、`--no-default-browser-check`。
- 已完成：Codex 全局 MCP 已新增 `chrome-devtools`，参数为 `npx -y chrome-devtools-mcp@latest --browser-url=http://127.0.0.1:9222`。
- 已完成：`config/chatgpt_chrome_window.ini`、`modules/chatgpt_chrome_window.ahk`、`modules/hotkey_help.ahk` 已接入 Chrome-CDP 参数、外链路由开关和二级托盘菜单。
- 已完成：新增 `tools/chatgpt_external_link_router.mjs`，通过 CDP openerId 只拦截 ChatGPT 页面打开的外部 http/https 链接，并转交 Firefox。
- 已验证：Chrome 9222 端口已返回 `Chrome/149.0.7827.200`；`chrome-devtools-mcp@latest --help` 可正常执行；外链路由脚本已真实连接 9222 并识别 Firefox 路径。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk`、`tests/hotkey_help_tests.ahk`、`tests/markdown_reference_link_inliner_tests.ahk`、`tests/sandbox_bridge_tests.ahk`、`tests/codex_profile_switcher_tests.ahk`、`main.ahk /Validate`、`node --check tools/chatgpt_external_link_router.mjs` 均通过或退出码为 0。

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
- 已完成：根据用户 2026-06-28 的二次反馈，默认模式已从 `window` 切为 `app`，默认尺寸改为 `540x760`，并新增“禁用右上角关闭按钮 + 托盘菜单显式彻底关闭”的防误关策略。
- 已完成：新增 `rect_policy_version` 状态迁移逻辑；即使本机 `logs/chatgpt_chrome_window_state.ini` 里残留的是旧的大窗矩形，只要它还没带上当前策略版本，就会自动回落到新的小窗默认值。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk`、`tests/hotkey_help_tests.ahk`、`tests/markdown_reference_link_inliner_tests.ahk`、`tests/sandbox_bridge_tests.ahk`、`tests/codex_profile_switcher_tests.ahk` 与 `main.ahk /Validate` 全部通过。
- 已验证：针对仓库内真实 `config/chatgpt_chrome_window.ini` 的非侵入冒烟已输出实际启动命令，确认当前默认行为为：`Default` Profile + `app` 模式 + `540x760` + `disable_close_button=1`；旧状态文件当前为 `rect_policy_version=0` 时，会解析成新的小窗矩形而不是继续沿用旧大窗。

## 2026-06-28 ChatGPT 浮窗单实例与切换语义修复

### 背景
- 新问题1：用户手测时同时出现两个 ChatGPT app 窗口，一个标题是会话名 `Quest 3 快速游戏推荐`，另一个标题是通用 `ChatGPT`，说明旧窗没有被当前逻辑重新接管，反而又新开了一个。
- 新问题2：当前切换语义是“可见但不在前台时，先激活；再次按才隐藏”。用户的直觉是“Alt+Space 就是开/关”，不希望先聚焦再按第二次才收起。
- 新问题3：跨虚拟桌面时，旧窗有时没有被正确接管，随后 Alt+Space 又新开一扇窗，最终演变成不可控多实例。
- 新问题4：`WinSetAlwaysOnTop` 仍存在窗口瞬间失效时的竞态报错，说明保护函数还缺少充足的 try/catch 与二次有效性判断。

### 根因判断
- 现有回收逻辑在 `last_hwnd` 失效后，会退回到“标题含 `ChatGPT`”的启发式识别。
- 但 ChatGPT app 窗口的标题会变成当前会话名，因此像 `Quest 3 快速游戏推荐` 这样的旧小窗不会命中该规则。
- 一旦旧窗未被认出，脚本就会误判为“当前没有受管浮窗”，继续 `Run --app=...` 新开一扇窗。

### 实现步骤
1. 收紧单实例识别逻辑：不再只靠标题含 `ChatGPT`，而是优先结合“Chrome 顶层窗口 + 置顶样式 + 历史矩形接近度 + 已保存句柄”做候选筛选。
2. 增加启动防抖/互斥：当一次 `Alt+Space` 还在“等待新窗出现”阶段时，短时间内忽略新的启动请求，防止手速快造成重复 `Run`。
3. 修改切换语义：只要受管窗当前可见，就直接收起；不再要求“先聚焦，再按第二次才隐藏”。
4. 为 `WinShow/WinMove/WinActivate/WinSetAlwaysOnTop/关闭按钮保护` 等外部窗口操作补竞态保护；一旦窗口中途失效，只清理受管状态，不再弹脚本级异常。
5. 补测试覆盖“会话标题窗口识别”、“可见即收起”、“启动防抖”和“保护函数遇到失效 hwnd 不抛异常”，再执行完整回归。

### 执行结果
- 已完成：`ChatGptChromeFindManagedWindowByHeuristic()` 不再只靠标题含 `ChatGPT`；现已引入“topmost + app 标题形态 + 历史矩形接近度”的综合候选评分，并额外偏向“具体会话名窗口”而不是泛化的 `ChatGPT` 首页标题。
- 已完成：新增“单实例守卫 + 重复实例收敛”逻辑；只要还能找到任何一个像受管浮窗的候选，后续就绝不再 `Run --app=...` 新窗，若现场已经误开出多个候选，则会自动收敛到首选实例，其余实例尝试关闭，失败时再隐藏兜底。
- 已完成：`Alt+Space` 的切换语义已调整为“只要当前受管窗可见，就直接收起”；不再要求先激活再按第二次。
- 已完成：新增启动防抖与互斥锁，避免连续快按或上一轮尚未等到窗口时重复 `Run --app=...`。
- 已完成：`WinShow/WinMove/WinActivate/WinSetAlwaysOnTop` 等路径已补竞态保护；若外部 Chrome 窗口在操作过程中失效，脚本会清理受管状态并安全返回，不再直接抛 `Target window not found`。
- 已完成：这一版已撤回 `tools/virtual_desktop_helper.ps1` 与对应调用链，不再依赖 PowerShell + C# 桥接虚拟桌面接口；跨桌面场景统一回退为“已有实例先收起、再在当前桌面重新展开”的简单逻辑。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk` 已增至 48 项并全部通过；`tests/hotkey_help_tests.ahk` 10 项通过；`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过；`tests/sandbox_bridge_tests.ahk` 11 项通过；`tests/codex_profile_switcher_tests.ahk` 与 `main.ahk /Validate` 也通过。

## 2026-06-28 ChatGPT 浮窗回归排障：热键变慢与跨桌面仍误开

### 背景
- 用户最新现场反馈明确指出两件事没有解决：
  - `Alt+Space` 现在明显“慢半拍”，不像上一轮那样立即响应。
  - 切换虚拟桌面后，依然会误开新的 ChatGPT 实例。
- 结合当前代码检查，已经能直接看到两个高风险点：
  - `ChatGptChromeToggleWindow()` 现在在热键主路径上无条件调用 `ChatGptChromeEnsureWindowOnCurrentVirtualDesktop()`，而该函数会同步拉起 PowerShell helper，并现场编译 C#，这是明显的慢路径。
  - 一旦 `ChatGptChromeEnsureWindowOnCurrentVirtualDesktop()` 返回 `false`，主流程会立刻 `ChatGptChromeForgetManagedWindow()`，后续就可能误判为“当前没有实例”并再次 `Run` 新窗。

### 修复步骤
1. 把“虚拟桌面判断/搬运”从每次热键必走，改成只在确实疑似“窗口在别的虚拟桌面”时才触发，恢复同桌面场景下的快速响应。
2. 去掉“helper 失败就忘掉旧 hwnd 并继续新开”的错误分支；受管窗口只要句柄还活着，就不允许因为跨桌面搬运失败而降级成新实例。
3. 增加更便宜的本地判定函数，先用同步成本很低的窗口状态判断是否需要进入跨桌面补救路径，避免每次都跑 PowerShell。
4. 补自动化测试覆盖：
   - 热路径不会默认依赖慢 helper；
   - 跨桌面补救失败时不会清空现有受管实例；
   - 发起新启动前，已有可用 hwnd 时仍会拒绝重复开窗。
5. 再跑 ChatGPT 模块测试、热键帮助测试、主脚本 `/Validate` 与现有相关回归，确认本轮没有把原有单实例语义打坏。

### 执行结果
- 已完成：`ChatGptChromeToggleWindow()` 的常规热路径已不再默认调用任何额外 helper；当前发现窗口疑似被 DWM cloak 时，也只走“hide/show 召回”的简单补救逻辑，不再桥接虚拟桌面 COM 接口。
- 已完成：新增 `ChatGptChromeHandleExistingWindow()`，把“已有实例”的恢复/隐藏/跨桌面召回统一收口；旧实例只要句柄还活着，就不会再因为跨桌面失败而被忘掉，更不会继续误开第二个实例。
- 已完成：新增 `ChatGptChromeGetWindowCloakedReason()` 与 `ChatGptChromeShouldAttemptDesktopRecall()`，先用本地 DWM 低成本判断筛掉绝大多数普通同桌面切换；一旦疑似留在别的桌面，就直接走 hide/show 召回，不再保留 PowerShell + C# helper。
- 已完成：启动防抖时间窗从 `1200ms` 收紧到 `250ms`；配合“已有 hwnd 优先处理”的主分支，热键体感已回到更接近上一轮的即时响应。
- 已完成：修正“误开新实例后窗口尺寸被污染”问题；现在新窗口出现后，会先 `WinMove` 到目标矩形，再写回状态文件，不再把 Chrome 自己恢复出来的错误大窗尺寸反写进记忆状态。
- 已完成：补充跨桌面门控纯逻辑测试，确保“可见且被 cloak 才尝试跨桌面补救；未 cloak 或不可见时不走慢路径”。
- 已验证：`tests/chatgpt_chrome_window_tests.ahk` 53 项通过、`tests/hotkey_help_tests.ahk` 10 项通过、`tests/markdown_reference_link_inliner_tests.ahk` 23 项通过、`tests/sandbox_bridge_tests.ahk` 11 项通过、`tests/codex_profile_switcher_tests.ahk` 通过，且 `main.ahk /Validate` 通过。

## 2026-06-23 Codex 中转预设统一改名为 OpenAI 并新增“何意味”

### 背景
- 目标：把现有中转型 Codex 预设的 provider 标识统一成 `OpenAI`，避免 `custom / right_code` 这类历史名字继续在 live `config.toml` 与共享模板回写里来回漂移。
- 新需求：
  - `海豹云-天才程序员` 与 `Right Code` 两套中转预设，后续都使用同一套 provider 名称：`OpenAI`。
  - `OpenAI Official` 仍保持“顶层不显式写 `model_provider`”的策略，但其 provider section 也要与模板侧统一到 `OpenAI`。
  - 新增一套显示名为 `何意味` 的中转预设，并按用户提供的 `OPENAI_API_KEY` 与 provider 模板初始化。
  - 地址分配按用户 2026-06-23 的更正执行：只有 `海豹云-天才程序员` 改为 `http://42.192.94.176:5002`；`何意味` 与 `Right Code` 保持 URL `https://ai.websee.top`；`OpenAI Official` 恢复为原先的 URL 方案，不跟随海豹云切到 IP。
- 当前问题：
  - `shared_template.enabled=1` 开启后，切换流程会按 `profiles.ini` 中声明的 provider patch 重建 `[model_providers.*]`，因此只改 live 或 secrets 里的单份 `config.toml` 不足以持久化。
  - 现有测试夹具与断言仍把 `custom / right_code` 视为预期值；若不一起更新，后续回归测试会全部失真。
- 预期结果：
  - `profiles.ini`、本机 secrets、live 配置与测试预期统一到新的 `OpenAI` 命名。
  - 新增 `何意味` 预设后，托盘菜单与校验流程能正常识别它。
  - 共享模板同步后，各预设只保留“是否顶层写 `model_provider`”与“各自 base_url”这类最小差异，不再保留旧命名，也不会再把所有预设误写成同一个 IP。

### 实现步骤
1. 更新 `config/codex_profiles/profiles.ini`，把中转预设的 `template_model_provider` / `template_provider_section_name` 统一改成 `OpenAI`，并补入 `何意味` 预设元数据。
2. 同步修正本机 `config/codex_profiles/secrets/*/config.toml` 与新增 `heyiwei` secrets，使现存预设和新预设在下次切换前就处于一致结构。
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
