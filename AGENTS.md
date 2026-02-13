# AGENTS

## 变更记录

- 2026-02-13：彻底修复聊天清洗模块中的连引号兼容性：在 `ChatStripTomlInlineComment` 与 `ChatParseTomlToken` 中统一改为 `Chr(34)/Chr(92)` 字符常量比较与替换，避免再次触发 `v1 script` 误判与 Reload 失败，更新 `modules/chat_message_cleaner.ahk`。
- 2026-02-13：修复 `ChatStripTomlInlineComment` 中双引号判定写法兼容性问题：将 `if (ch = \"\"\"\")` 改为 `if (ch = Chr(34))`，避免部分环境误报 v1 语法并导致 Reload 失败，更新 `modules/chat_message_cleaner.ahk`。
- 2026-02-13：修复聊天昵称 TOML 示例注释格式为标准 `#`（避免编辑器 `unexpected token`），并同步将聊天清洗热键改为 `Ctrl+Win+C`，更新 `config/chat_name_alias.toml`、`modules/chat_message_cleaner.ahk`、`modules/hotkeys.ahk`。
- 2026-02-13：新增聊天消息清洗复制热键 `Ctrl+Alt+Q`，支持 QQ/微信复制文本去时间戳、消息按行压平、按条数提示，并引入外置 `config/chat_name_alias.toml` 昵称映射（按键时实时读取，无需 Reload），更新 `modules/chat_message_cleaner.ahk`、`modules/hotkeys.ahk`、`config/chat_name_alias.toml`。
- 2026-02-13：调整沙盒中转 `Ctrl+Alt+V` 行为：无任务状态下也可直接执行目录级手动清理（扫描 `__AHK_Transit__` 残留并删除），仅在无残留时提示“无可清理项”，更新 `modules/sandbox_bridge.ahk`。
- 2026-02-13：按调试反馈将 `Toast` 改为仅 `ToolTip`（移除系统 `TrayTip`），并修复沙盒中转 `Ctrl+Alt+V` 流程冲突：双击清理优先于粘贴判定，多文件清理支持任意窗口触发，更新 `modules/utils.ahk`、`modules/sandbox_bridge.ahk`。
- 2026-02-13：恢复沙盒中转热键为 `Ctrl+Alt+C / Ctrl+Alt+V`（确认当前无占用冲突），抽离 Spotify 工具函数到 `modules/spotify_controls.ahk` 以精简热键清单，删除空文件 `modules/watch_downloads_simple.ahk`，并修正 `modules/watch_downloads.ahk` 扫描间隔注释为 1000ms。
- 2026-02-13：新增微信/QQ 沙盒文件中转模块与热键（Ctrl+Alt+C / Ctrl+Alt+V），支持单文件自动粘贴与延时清理、多文件双击清理；修复窗口交集计算下边界错误，更新 `modules/sandbox_bridge.ahk`、`modules/hotkeys.ahk`、`modules/window_switch.ahk`。
- 2026-01-14：调整 Spotify 切换逻辑为“先判定最小化，再判定前台”，避免最小化仍前台导致反复最小化，更新 `modules/hotkeys.ahk`。
- 2025-12-30：新增 Spotify 前台显示/最小化切换逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：新增 Ctrl+X 分流与 Spotify 唤起逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：修复 Ctrl+X+Space 分流与 Ctrl+Space 冲突，完善状态清理逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：调整 Ctrl+X 分流为条件化 <^Space，移除过早清理以恢复剪切，更新 `modules/hotkeys.ahk`。
