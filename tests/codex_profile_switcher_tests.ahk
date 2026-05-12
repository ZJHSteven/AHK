#Requires AutoHotkey v2.0
; ============================================
; Codex 预设切换模块测试
; --------------------------------------------
; 这个测试只使用 A_Temp 下的临时目录，不读写真实 %USERPROFILE%\.codex。
; ============================================

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
        CodexProfileTestValidationCache(root)
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

[openai_official]
display_name=OpenAI Official
auth_path=secrets\openai_official\auth.json
config_path=secrets\openai_official\config.toml

[right_code]
display_name=Right Code
auth_path=secrets\right_code\auth.json
config_path=secrets\right_code\config.toml
    )"
    CodexProfileWriteText(root "\profiles.ini", manifest)

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

CodexProfileTestValidationCache(root) {
    global g_CodexProfilesValidationRunCount
    profiles := CodexProfilesLoadManifest(root)
    g_CodexProfilesValidationRunCount := 0

    first := CodexProfileValidateIfNeeded(profiles[1], root)
    CodexProfileAssertTrue(first["ok"], "首次校验应通过")
    CodexProfileAssertEqual(g_CodexProfilesValidationRunCount, 1, "首次校验应启动 Python")

    second := CodexProfileValidateIfNeeded(profiles[1], root)
    CodexProfileAssertTrue(second["ok"], "缓存校验应通过")
    CodexProfileAssertEqual(g_CodexProfilesValidationRunCount, 1, "文件未变化时不应再次启动 Python")
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

