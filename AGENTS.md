# AGENTS

## 变更记录

- 2026-01-14：调整 Spotify 切换逻辑为“先判定最小化，再判定前台”，避免最小化仍前台导致反复最小化，更新 `modules/hotkeys.ahk`。
- 2025-12-30：新增 Spotify 前台显示/最小化切换逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：新增 Ctrl+X 分流与 Spotify 唤起逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：修复 Ctrl+X+Space 分流与 Ctrl+Space 冲突，完善状态清理逻辑，更新 `modules/hotkeys.ahk`。
- 2025-12-30：调整 Ctrl+X 分流为条件化 <^Space，移除过早清理以恢复剪切，更新 `modules/hotkeys.ahk`。
