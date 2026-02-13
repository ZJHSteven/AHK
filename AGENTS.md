# AGENTS

## 变更记录

- 2026-02-13：按调试反馈将 `Toast` 改为仅 `ToolTip`（移除系统 `TrayTip`），并修复沙盒中转 `Ctrl+Alt+V` 流程冲突：双击清理优先于粘贴判定，多文件清理支持任意窗口触发，更新 `modules/utils.ahk`、`modules/sandbox_bridge.ahk`。
- 2026-02-13：恢复沙盒中转热键为 `Ctrl+Alt+C / Ctrl+Alt+V`（确认当前无占用冲突），抽离 Spotify 工具函数到 `modules/spotify_controls.ahk` 以精简热键清单，删除空文件 `modules/watch_downloads_simple.ahk`，并修正 `modules/watch_downloads.ahk` 扫描间隔注释为 1000ms。
- 2026-02-13：新增微信/QQ 沙盒文件中转模块与热键（Ctrl+Alt+C / Ctrl+Alt+V），支持单文件自动粘贴与延时清理、多文件双击清理；修复窗口交集计算下边界错误，更新 `modules/sandbox_bridge.ahk`、`modules/hotkeys.ahk`、`modules/window_switch.ahk`。
- 2026-01-14：调整 Spotify 切换逻辑为“先判定最小化，再判定前台”，避免最小化仍前台导致反复最小化，更新 `modules/hotkeys.ahk`。
- 2025-12-30：新增 Spotify 前台显示/最小化切换逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：新增 Ctrl+X 分流与 Spotify 唤起逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：修复 Ctrl+X+Space 分流与 Ctrl+Space 冲突，完善状态清理逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：调整 Ctrl+X 分流为条件化 <^Space，移除过早清理以恢复剪切，更新 `modules/hotkeys.ahk`。
