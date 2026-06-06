#Requires AutoHotkey v2.0
; ============================================
; Codex 预设切换模块测试
; --------------------------------------------
; 这个测试只使用 A_Temp 下的临时目录，不读写真实 %USERPROFILE%\.codex。
; ============================================

#Include ..\modules\utils.ahk
#Include ..\modules\codex_profile_switcher.ahk

global g_TestPassCount := 0

try {
    CodexProfileRunAllTests()
    FileAppend("OK: " g_TestPassCount " tests passed.`n", "*", "UTF-8")
    ExitApp(0)
} catch as err {
    FileAppend("FAIL: " err.Message "`n", "*", "UTF-8")
    ExitApp(1)
}

CodexProfileRunAllTests() {
    root := A_Temp "\ahk_codex_profile_tests_" A_TickCount
    liveDir := root "\live"
    try {
        CodexProfileCreateFixture(root, liveDir)
        CodexProfileTestManifestParse(root)
        CodexProfileTestConfiguredDetection(root)
        CodexProfileTestActiveDetection(root, liveDir)
        CodexProfileTestActiveDetectionAcceptsAuthRefresh(root, liveDir)
        CodexProfileTestTrayMenuCanBeBuilt(root, liveDir)
        CodexProfileTestValidationCache(root)
        CodexProfileTestSwitchSyncsLiveFilesBackToSource(root, liveDir)
        CodexProfileTestSwitchFallsBackToLastSwitchForFullConfigSync(root, liveDir)
        CodexProfileTestSharedTemplateSyncsAllProfiles(root, liveDir)
        CodexProfileTestSwitchWritesBackupAndLive(root, liveDir)
        CodexProfileTestInvalidProfileDoesNotChangeLive(root, liveDir)
    } finally {
        if DirExist(root) {
            try DirDelete(root, true)
        }
    }
}

CodexProfileAssertEqual(actual, expected, caseName) {
    global g_TestPassCount
    if (actual != expected) {
        throw Error(caseName " 断言失败。期望：" expected "，实际：" actual)
    }
    g_TestPassCount += 1
}

CodexProfileAssertTrue(value, caseName) {
    global g_TestPassCount
    if !value {
        throw Error(caseName " 断言失败：结果应为 true。")
    }
    g_TestPassCount += 1
}

CodexProfileAssertFalse(value, caseName) {
    global g_TestPassCount
    if value {
        throw Error(caseName " 断言失败：结果应为 false。")
    }
    g_TestPassCount += 1
}

CodexProfileWriteText(path, text) {
    SplitPath(path, , &dir)
    if !DirExist(dir) {
        DirCreate(dir)
    }
    if FileExist(path) {
        FileDelete(path)
    }
    FileAppend(text, path, "UTF-8")
}

CodexProfileCreateFixture(root, liveDir) {
    DirCreate(root)
    DirCreate(liveDir)

    manifest := "
    (
[haibao]
display_name=海豹云-天才程序员
auth_path=secrets\haibao\auth.json
config_path=secrets\haibao\config.toml
template_model_provider=custom
template_provider_section_name=custom
template_provider_base_url=https://code.rpgame.net
template_provider_wire_api=responses
template_provider_requires_openai_auth=true

[openai_official]
display_name=OpenAI Official
auth_path=secrets\openai_official\auth.json
config_path=secrets\openai_official\config.toml
template_model_provider=
template_provider_section_name=custom
template_provider_base_url=https://code.rpgame.net
template_provider_wire_api=responses
template_provider_requires_openai_auth=true

[right_code]
display_name=Right Code
auth_path=secrets\right_code\auth.json
config_path=secrets\right_code\config.toml
template_model_provider=right_code
template_provider_section_name=right_code
template_provider_base_url=https://www.right.codes/codex/v1
template_provider_wire_api=responses
template_provider_requires_openai_auth=true
    )"
    CodexProfileWriteText(root "\profiles.ini", manifest)
    CodexProfileWriteText(root "\settings.ini", "[shared_template]`nenabled=0`nmember_ids=haibao,openai_official,right_code`n")

    CodexProfileWriteText(root "\secrets\haibao\auth.json", "{`"OPENAI_API_KEY`":`"haibao-key`"}")
    CodexProfileWriteText(root "\secrets\haibao\config.toml", "model_provider = `"custom`"`nmodel = `"gpt-test`"`n")

    CodexProfileWriteText(root "\secrets\openai_official\auth.json", "{`"OPENAI_API_KEY`":`"official-key`"}")
    CodexProfileWriteText(root "\secrets\openai_official\config.toml", "model_provider = `"openai`"`nmodel = `"gpt-official`"`n")

    CodexProfileWriteText(root "\secrets\right_code\auth.json", "{bad json")
    CodexProfileWriteText(root "\secrets\right_code\config.toml", "model = `"broken`"`n")

    CodexProfileWriteText(liveDir "\auth.json", "{`"OPENAI_API_KEY`":`"haibao-key`"}")
    CodexProfileWriteText(liveDir "\config.toml", "model_provider = `"custom`"`nmodel = `"gpt-test`"`n")
}

CodexProfileTestManifestParse(root) {
    profiles := CodexProfilesLoadManifest(root)
    CodexProfileAssertEqual(profiles.Length, 3, "应解析三套预设")
    CodexProfileAssertEqual(profiles[1]["id"], "haibao", "第一套 id")
    CodexProfileAssertEqual(profiles[1]["displayName"], "海豹云-天才程序员", "第一套中文显示名")
    CodexProfileAssertTrue(InStr(profiles[2]["authPath"], "openai_official\auth.json"), "第二套 auth 路径")
}

CodexProfileTestConfiguredDetection(root) {
    profiles := CodexProfilesLoadManifest(root)
    CodexProfileAssertTrue(CodexProfileIsConfigured(profiles[1]), "完整预设应被视为已配置")

    FileDelete(profiles[2]["authPath"])
    CodexProfileAssertFalse(CodexProfileIsConfigured(profiles[2]), "缺 auth 文件应被视为未配置")
    CodexProfileWriteText(profiles[2]["authPath"], "{`"OPENAI_API_KEY`":`"official-key`"}")
}

CodexProfileTestActiveDetection(root, liveDir) {
    activeId := CodexProfilesDetectActiveId(root, liveDir)
    CodexProfileAssertEqual(activeId, "haibao", "live 应匹配海豹云预设")

    CodexProfileWriteText(liveDir "\config.toml", "model = `"manual-change`"`n")
    activeId := CodexProfilesDetectActiveId(root, liveDir)
    CodexProfileAssertEqual(activeId, "", "外部改动后不应误报当前预设")

    CodexProfileWriteText(liveDir "\config.toml", "model_provider = `"custom`"`nmodel = `"gpt-test`"`n")
}

CodexProfileTestActiveDetectionAcceptsAuthRefresh(root, liveDir) {
    refreshedAuth := "{`"OPENAI_API_KEY`":`"haibao-key`",`"auth_mode`":`"login`",`"last_refresh`":`"2026-05-29T09:00:00Z`",`"tokens`":{`"refresh_token`":`"new-refresh-token`"}}"
    CodexProfileWriteText(liveDir "\auth.json", refreshedAuth)

    activeId := CodexProfilesDetectActiveId(root, liveDir)
    CodexProfileAssertEqual(activeId, "haibao", "仅 auth 因 refresh 漂移时，仍应识别为当前海豹云预设")

    CodexProfileWriteText(liveDir "\auth.json", "{`"OPENAI_API_KEY`":`"haibao-key`"}")
}

CodexProfileTestTrayMenuCanBeBuilt(root, liveDir) {
    ; 这个用例专门覆盖真实托盘初始化会走到的菜单构造路径。
    ; 之前的问题是局部变量 menu 遮蔽了 AHK 内置 Menu 类，
    ; 普通语法校验不会发现，只有运行到 CodexProfilesBuildTrayMenu() 才会报错。
    trayMenu := CodexProfilesBuildTrayMenu(root, liveDir)
    CodexProfileAssertTrue(IsObject(trayMenu), "Codex 预设托盘子菜单应能成功构造")
}

CodexProfileTestValidationCache(root) {
    global g_CodexProfilesValidationRunCount
    profiles := CodexProfilesLoadManifest(root)
    g_CodexProfilesValidationRunCount := 0

    first := CodexProfileValidateIfNeeded(profiles[1], root)
    CodexProfileAssertTrue(first["ok"], "首次校验应通过：" first["message"])
    CodexProfileAssertEqual(g_CodexProfilesValidationRunCount, 1, "首次校验应启动 Python")

    second := CodexProfileValidateIfNeeded(profiles[1], root)
    CodexProfileAssertTrue(second["ok"], "缓存校验应通过")
    CodexProfileAssertEqual(g_CodexProfilesValidationRunCount, 1, "文件未变化时不应再次启动 Python")
}

CodexProfileTestSwitchSyncsLiveFilesBackToSource(root, liveDir) {
    refreshedAuth := "{`"OPENAI_API_KEY`":`"haibao-key`",`"auth_mode`":`"login`",`"last_refresh`":`"2026-05-29T09:00:00Z`",`"tokens`":{`"refresh_token`":`"new-refresh-token`"}}"
    CodexProfileWriteText(liveDir "\auth.json", refreshedAuth)
    originalConfig := "model_provider = `"custom`"`nmodel = `"gpt-test`"`n"

    result := CodexProfilesSwitch("openai_official", root, liveDir)
    CodexProfileAssertTrue(result["ok"], "切换前应先把来源预设整文件回写成功")
    CodexProfileAssertEqual(FileRead(root "\secrets\haibao\auth.json", "UTF-8"), refreshedAuth, "来源预设 auth 应被同步成最新 live token")
    CodexProfileAssertEqual(FileRead(root "\secrets\haibao\config.toml", "UTF-8"), originalConfig, "config 未漂移时，来源预设 config 也应保持与 live 一致")
}

CodexProfileTestSwitchFallsBackToLastSwitchForFullConfigSync(root, liveDir) {
    profiles := CodexProfilesLoadManifest(root)
    CodexProfilesWriteLastSwitchState(root, profiles[1])

    refreshedAuth := "{`"OPENAI_API_KEY`":`"haibao-key`",`"auth_mode`":`"login`",`"last_refresh`":`"2026-06-06T07:44:38Z`",`"tokens`":{`"refresh_token`":`"last-switch-token`"}}"
    driftedConfig := "model_provider = `"custom`"`nmodel = `"manual-drift`"`nmodel_reasoning_effort = `"low`"`n"
    CodexProfileWriteText(liveDir "\auth.json", refreshedAuth)
    CodexProfileWriteText(liveDir "\config.toml", driftedConfig)

    activeId := CodexProfilesDetectActiveId(root, liveDir)
    CodexProfileAssertEqual(activeId, "", "config 漂移后，托盘当前态识别仍应保持保守")

    result := CodexProfilesSwitch("openai_official", root, liveDir)
    CodexProfileAssertTrue(result["ok"], "即使 config 已漂移，仍应依赖 last_switch 回写来源整文件")
    CodexProfileAssertEqual(FileRead(root "\secrets\haibao\auth.json", "UTF-8"), refreshedAuth, "last_switch 兜底时也应回写来源 auth")
    CodexProfileAssertEqual(FileRead(root "\secrets\haibao\config.toml", "UTF-8"), driftedConfig, "last_switch 兜底时也应回写来源 config")
}

CodexProfileTestSharedTemplateSyncsAllProfiles(root, liveDir) {
    sharedSourceConfig := "
    (
model_provider = "custom"
personality = "pragmatic"
model = "gpt-shared"
model_reasoning_effort = "high"

[model_providers]
[model_providers.custom]
name = "custom"
base_url = "https://code.rpgame.net"
wire_api = "responses"
requires_openai_auth = true

[marketplaces]
[marketplaces.openai-bundled]
last_updated = "2026-06-07T01:02:03Z"
source_type = "local"
source = '\\?\C:\Users\ZJHSteven\.codex\.tmp\bundled-marketplaces\openai-bundled'

[plugins."browser@openai-bundled"]
enabled = false
    )"
    officialBefore := "
    (
personality = "pragmatic"
model = "gpt-old-official"

[model_providers]
[model_providers.custom]
name = "custom"
base_url = "https://code.rpgame.net"
wire_api = "responses"
requires_openai_auth = true

[marketplaces]
[marketplaces.openai-bundled]
last_updated = "2026-01-01T00:00:00Z"
source_type = "local"
source = '\\?\C:\Users\ZJHSteven\.codex\.tmp\bundled-marketplaces\openai-bundled'

[plugins."browser@openai-bundled"]
enabled = true
    )"
    rightCodeBefore := "
    (
model_provider = "right_code"
disable_response_storage = true
personality = "pragmatic"
model = "gpt-old-right-code"

[model_providers]
[model_providers.right_code]
name = "right_code"
base_url = "https://www.right.codes/codex/v1"
wire_api = "responses"
requires_openai_auth = true

[marketplaces]
[marketplaces.openai-bundled]
last_updated = "2026-01-01T00:00:00Z"
source_type = "local"
source = '\\?\C:\Users\ZJHSteven\.codex\.tmp\bundled-marketplaces\openai-bundled'

[plugins."browser@openai-bundled"]
enabled = true
    )"

    CodexProfileWriteText(root "\settings.ini", "[shared_template]`nenabled=1`nmember_ids=haibao,openai_official,right_code`n")
    CodexProfileWriteText(root "\secrets\haibao\config.toml", sharedSourceConfig)
    CodexProfileWriteText(root "\secrets\openai_official\config.toml", officialBefore)
    CodexProfileWriteText(root "\secrets\right_code\auth.json", "{`"OPENAI_API_KEY`":`"right-code-key`"}")
    CodexProfileWriteText(root "\secrets\right_code\config.toml", rightCodeBefore)
    CodexProfileWriteText(liveDir "\auth.json", "{`"OPENAI_API_KEY`":`"haibao-key`",`"auth_mode`":`"login`"}")
    CodexProfileWriteText(liveDir "\config.toml", sharedSourceConfig)

    result := CodexProfilesSwitch("openai_official", root, liveDir)
    CodexProfileAssertTrue(result["ok"], "开启通用模板后，切换应成功并同步三套预设")

    officialAfter := FileRead(root "\secrets\openai_official\config.toml", "UTF-8")
    haibaoAfter := FileRead(root "\secrets\haibao\config.toml", "UTF-8")
    rightCodeAfter := FileRead(root "\secrets\right_code\config.toml", "UTF-8")

    quotedSharedModel := "model = " Chr(34) "gpt-shared" Chr(34)
    quotedSharedUpdatedAt := "last_updated = " Chr(34) "2026-06-07T01:02:03Z" Chr(34)
    quotedCustomProvider := "model_provider = " Chr(34) "custom" Chr(34)
    quotedRightCodeProvider := "model_provider = " Chr(34) "right_code" Chr(34)
    quotedRightCodeBaseUrl := "base_url = " Chr(34) "https://www.right.codes/codex/v1" Chr(34)

    CodexProfileAssertTrue(InStr(officialAfter, quotedSharedModel), "Official 应同步公共 model")
    CodexProfileAssertTrue(InStr(officialAfter, quotedSharedUpdatedAt), "Official 应同步公共 marketplace 时间戳")
    CodexProfileAssertFalse(InStr(officialAfter, quotedCustomProvider), "Official 不应保留 custom 顶层 provider")

    CodexProfileAssertTrue(InStr(haibaoAfter, quotedCustomProvider), "海豹云应保留 custom 顶层 provider")
    CodexProfileAssertTrue(InStr(haibaoAfter, "enabled = false"), "海豹云应同步公共 plugin 开关")

    CodexProfileAssertTrue(InStr(rightCodeAfter, quotedRightCodeProvider), "RC 应改写成 right_code 顶层 provider")
    CodexProfileAssertTrue(InStr(rightCodeAfter, "[model_providers.right_code]"), "RC 应改写成 right_code provider section")
    CodexProfileAssertTrue(InStr(rightCodeAfter, quotedRightCodeBaseUrl), "RC 应保留自己的 provider base_url")
    CodexProfileAssertFalse(InStr(rightCodeAfter, "disable_response_storage = true"), "RC 的旧私有差异应被公共模板抹平")

    CodexProfileWriteText(root "\settings.ini", "[shared_template]`nenabled=0`nmember_ids=haibao,openai_official,right_code`n")
    CodexProfileWriteText(root "\secrets\right_code\auth.json", "{bad json")
}

CodexProfileTestSwitchWritesBackupAndLive(root, liveDir) {
    result := CodexProfilesSwitch("openai_official", root, liveDir)
    CodexProfileAssertTrue(result["ok"], "切换 OpenAI Official 应成功")
    CodexProfileAssertTrue(FileExist(result["backupDir"] "\auth.json"), "切换前应备份 auth")
    CodexProfileAssertTrue(FileExist(result["backupDir"] "\config.toml"), "切换前应备份 config")

    activeId := CodexProfilesDetectActiveId(root, liveDir)
    CodexProfileAssertEqual(activeId, "openai_official", "切换后 live 应匹配目标预设")
}

CodexProfileTestInvalidProfileDoesNotChangeLive(root, liveDir) {
    beforeAuth := FileRead(liveDir "\auth.json", "UTF-8")
    beforeConfig := FileRead(liveDir "\config.toml", "UTF-8")
    result := CodexProfilesSwitch("right_code", root, liveDir)

    CodexProfileAssertFalse(result["ok"], "非法 JSON 预设不应切换成功")
    CodexProfileAssertEqual(FileRead(liveDir "\auth.json", "UTF-8"), beforeAuth, "失败后 auth 不应变化")
    CodexProfileAssertEqual(FileRead(liveDir "\config.toml", "UTF-8"), beforeConfig, "失败后 config 不应变化")
}
