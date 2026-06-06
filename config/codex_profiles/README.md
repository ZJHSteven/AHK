# Codex 预设目录说明

这个目录用于 AHK 的 Codex 预设切换功能。

- `profiles.ini`：可提交的预设清单，只保存显示名和相对路径，不保存密钥。
- `secrets/<profile_id>/auth.json`：本机真实 Codex 登录/API Key 文件，已被 `.gitignore` 忽略。
- `secrets/<profile_id>/config.toml`：本机真实 Codex 配置文件，已被 `.gitignore` 忽略。
- `settings.ini`：可提交的同步策略设置；当前用于控制三套 provider 预设是否启用“通用模板同步”。
- `state.ini`：校验缓存，已被 `.gitignore` 忽略。
- `backups/`：每次切换前自动保存的 live 配置备份，已被 `.gitignore` 忽略。

切换行为说明：

- 每次真正切换前，脚本会先识别“当前 live 大概率来自哪套预设”。
- 若只是 `auth.json` 因 refresh token 自动刷新而和 secrets 里的旧文件不再完全一致，但 `config.toml` 仍一致，脚本仍会把它识别成同一套预设。
- 若 live 已被手改到不再字节匹配任何预设，切换前会退回到 `state.ini` 记录的 `last_switch` 作为“当前来源预设”兜底，优先保住运行时改动。
- 一旦识别成功，脚本会先把当前 live `auth.json` 回写到来源预设，避免下次切回时又退回旧 token。
- `config.toml` 的同步取决于 `settings.ini`：
  - `shared_template.enabled=0` 时：只把当前 live `config.toml` 回写到来源预设。
  - `shared_template.enabled=1` 时：把当前 live `config.toml` 视为“公共模板来源”，再对 `member_ids` 里的每套预设套用各自 provider 差异，自动追平三套预设的公共配置。
- 当前三套 provider 预设的 provider 差异来自 `profiles.ini`：
  - `haibao`：`model_provider=custom`，并重建 `[model_providers.custom]`
  - `openai_official`：移除顶层 `model_provider`，其余公共配置与模板保持一致
  - `right_code`：`model_provider=right_code`，并重建 `[model_providers.right_code]`

第一套 `海豹云-天才程序员` 会在脚本启动时尝试从 `%USERPROFILE%\.codex` 复制当前 live 配置初始化；另外两套需要手动放入对应的 `auth.json` 与 `config.toml` 后才会在托盘菜单里启用。
