# Codex 预设目录说明

这个目录用于 AHK 的 Codex 预设切换功能。

- `profiles.ini`：可提交的预设清单，只保存显示名和相对路径，不保存密钥。
- `secrets/<profile_id>/auth.json`：本机真实 Codex 登录/API Key 文件，已被 `.gitignore` 忽略。
- `secrets/<profile_id>/config.toml`：本机真实 Codex 配置文件，已被 `.gitignore` 忽略。
- `state.ini`：校验缓存，已被 `.gitignore` 忽略。
- `backups/`：每次切换前自动保存的 live 配置备份，已被 `.gitignore` 忽略。

切换行为说明：

- 每次真正切换前，脚本会先识别“当前 live 大概率来自哪套预设”。
- 若只是 `auth.json` 因 refresh token 自动刷新而和 secrets 里的旧文件不再完全一致，但 `config.toml` 仍一致，脚本仍会把它识别成同一套预设。
- 一旦识别成功，脚本会先把当前 live `auth.json` 回写到对应 `secrets/<profile_id>/auth.json`，再覆盖到目标预设，避免下次切回时又退回旧 token。
- `config.toml` 默认不会自动回写，因为它更像人工维护的预设定义；若自动同步，反而可能把临时漂移或错误 MCP 配置固化回 secrets。

第一套 `海豹云-天才程序员` 会在脚本启动时尝试从 `%USERPROFILE%\.codex` 复制当前 live 配置初始化；另外两套需要手动放入对应的 `auth.json` 与 `config.toml` 后才会在托盘菜单里启用。
