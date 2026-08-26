#requires -Version 7.0
<#
.SYNOPSIS
    将当前 AHK 登录常驻任务从“普通解释器 + Highest”迁移为“UIAccess 解释器 + Limited”。

.DESCRIPTION
    该脚本只操作 Action 参数指向 D:\Workspace\AHK\main.ahk 的唯一计划任务：
    1. 要求自身已管理员运行；
    2. 导出现有 Task XML 到 logs\task-backups；
    3. 将解释器切换为 AutoHotkey64_UIA.exe；
    4. 将 Principal.RunLevel 切换为 Limited；
    5. 停止旧的管理员 AHK 实例并重新启动该任务；
    6. 回读 Task 配置及 AHK runtime 日志做最小验收。

    这里不修改 Trigger、RestartOnFailure、MultipleInstancesPolicy 等已有可靠性设置。
#>

$ErrorActionPreference = 'Stop'

$scriptPath = 'D:\Workspace\AHK\main.ahk'
$uiaExe = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe'
$backupDir = 'D:\Workspace\AHK\logs\task-backups'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '本迁移脚本必须在管理员 PowerShell 中执行。'
    }
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $uiaExe -PathType Leaf)) {
    throw "找不到 UIAccess 解释器：$uiaExe"
}

$matches = @(
    Get-ScheduledTask | Where-Object {
        foreach ($action in $_.Actions) {
            if ($action.Arguments -and $action.Arguments.Trim('"') -ieq $scriptPath) {
                return $true
            }
        }
        return $false
    }
)

if ($matches.Count -ne 1) {
    throw "预期只找到 1 个指向 $scriptPath 的计划任务，实际找到 $($matches.Count) 个。为避免误改，已停止。"
}

$task = $matches[0]
Write-Host "找到任务：$($task.TaskPath)$($task.TaskName)"
Write-Host "原 RunLevel：$($task.Principal.RunLevel)"
Write-Host "原 Execute：$($task.Actions[0].Execute)"
Write-Host "原 Arguments：$($task.Actions[0].Arguments)"

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path $backupDir "ahk-task-before-uiaccess-$timestamp.xml"
Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath |
    Set-Content -LiteralPath $backupPath -Encoding Unicode
Write-Host "已备份：$backupPath"

$newAction = New-ScheduledTaskAction -Execute $uiaExe -Argument ('"{0}"' -f $scriptPath)
$newPrincipal = New-ScheduledTaskPrincipal `
    -UserId $task.Principal.UserId `
    -LogonType Interactive `
    -RunLevel Limited

Set-ScheduledTask `
    -TaskName $task.TaskName `
    -TaskPath $task.TaskPath `
    -Action $newAction `
    -Principal $newPrincipal | Out-Null

# 先停止旧任务（旧管理员 AHK），再由更新后的任务定义拉起 UIAccess/Medium 实例。
Stop-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Start-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
Start-Sleep -Seconds 2

$updated = Get-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
$info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath

Write-Host ''
Write-Host '=== 更新后 ==='
Write-Host "RunLevel：$($updated.Principal.RunLevel)"
Write-Host "Execute：$($updated.Actions[0].Execute)"
Write-Host "Arguments：$($updated.Actions[0].Arguments)"
Write-Host "State：$($updated.State)"
Write-Host ('LastTaskResult：0x{0:X8}' -f ([uint32]$info.LastTaskResult))

$processes = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64_UIA.exe'")
Write-Host "UIA AHK 进程数：$($processes.Count)"
foreach ($process in $processes) {
    Write-Host "  PID=$($process.ProcessId) CommandLine=$($process.CommandLine)"
}

if ($updated.Principal.RunLevel -ne 'Limited') {
    throw '迁移失败：RunLevel 不是 Limited。'
}
if ($updated.Actions[0].Execute.Trim('"') -ine $uiaExe) {
    throw '迁移失败：Action 未指向 AutoHotkey64_UIA.exe。'
}
if ($processes.Count -ne 1) {
    throw "迁移后预期恰好 1 个 AutoHotkey64_UIA.exe，实际 $($processes.Count) 个。"
}

Write-Host ''
Write-Host 'AHK UIAccess 降权迁移完成。'
