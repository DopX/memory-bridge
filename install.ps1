<#
.SYNOPSIS
    Memory Bridge 安装脚本

.DESCRIPTION
    将 Memory Bridge hooks 安装到各 AI 客户端配置中。
    支持安装和卸载。

.PARAMETER Config
    config.yaml 的路径（默认当前目录）

.PARAMETER Uninstall
    回滚安装，恢复备份的配置文件

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Config "D:\path\to\config.yaml"
    .\install.ps1 -Uninstall

.NOTES
    需要 PowerShell 7+
#>

param(
    [string]$Config,
    [switch]$Uninstall
)

# 强制使用 UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 获取脚本所在目录（即 INSTALL_DIR）
$InstallDir = $PSScriptRoot
$ClientsDir = Join-Path $InstallDir "clients"
$BackupDir = Join-Path $env:USERPROFILE ".memory-bridge\backups"

# 获取配置路径
if (-not $Config) {
    $Config = Join-Path $InstallDir "config.yaml"
}

if (-not (Test-Path $Config)) {
    Write-Error "配置文件未找到: $Config"
    exit 1
}

# 读取配置
Write-Host "读取配置: $Config"
$config = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $config) {
    Write-Error "配置文件格式无效"
    exit 1
}

# 客户端配置路径映射
$ClientPaths = @{
    "claude-code" = Join-Path $env:USERPROFILE ".claude\settings.json"
    "qoder" = Join-Path $env:USERPROFILE ".qoder\settings.json"
    "codebuddy" = Join-Path $env:USERPROFILE ".codebuddy\settings.json"
    "cursor" = Join-Path $env:USERPROFILE ".cursor\hooks.json"
    "codex" = Join-Path $env:USERPROFILE ".codex\hooks.json"
    "windsurf" = Join-Path $env:USERPROFILE ".codeium\windsurf\hooks.json"
    "gemini" = Join-Path $env:USERPROFILE ".gemini\settings.json"
    "trae" = $null  # 待确认
    "copilot" = $null  # VS Code 插件机制
}

# 卸载函数
function Uninstall-Client {
    param([string]$ClientName, [string]$ConfigPath)

    Write-Host "卸载 $ClientName hooks..."

    # 查找最新的备份
    $backupPattern = Join-Path $BackupDir "$ClientName-*.json"
    $backups = Get-ChildItem -Path $backupPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    if (-not $backups -or $backups.Count -eq 0) {
        Write-Warning "  未找到备份文件，跳过"
        return
    }

    $latestBackup = $backups[0]
    Write-Host "  恢复备份: $($latestBackup.Name)"

    # 恢复备份
    Copy-Item $latestBackup.FullName $ConfigPath -Force
    Write-Host "  已恢复"
}

# 安装函数
function Install-Client {
    param([string]$ClientName, [string]$ConfigPath)

    Write-Host "安装 $ClientName hooks..."

    # 检查客户端模板
    $templatePath = Join-Path $ClientsDir "$ClientName.json"
    if (-not (Test-Path $templatePath)) {
        Write-Warning "  模板文件未找到: $templatePath"
        return
    }

    # 读取模板
    $template = Get-Content $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $template -or -not $template.hooks) {
        Write-Warning "  模板格式无效"
        return
    }

    # 备份现有配置
    if (Test-Path $ConfigPath) {
        if (-not (Test-Path $BackupDir)) {
            New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        }

        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = Join-Path $BackupDir "$ClientName-$timestamp.json"
        Copy-Item $ConfigPath $backupPath -Force
        Write-Host "  已备份到: $backupPath"
    }

    # 替换占位符
    $configDir = Split-Path $Config -Parent
    $configFullPath = Resolve-Path $Config

    $hooksJson = $template.hooks | ConvertTo-Json -Depth 10
    $hooksJson = $hooksJson -replace "INSTALL_DIR", ($InstallDir -replace '\\', '\\\\')
    $hooksJson = $hooksJson -replace "CONFIG_PATH", ($configFullPath -replace '\\', '\\\\')
    $hooks = $hooksJson | ConvertFrom-Json

    # 读取现有配置（如果存在）
    $existingConfig = @{}
    if (Test-Path $ConfigPath) {
        $existingConfig = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
        if (-not $existingConfig) {
            $existingConfig = @{}
        }
    }

    # 合并 hooks（追加不覆盖）
    if (-not $existingConfig.hooks) {
        $existingConfig.hooks = @{}
    }

    foreach ($event in $hooks.PSObject.Properties) {
        $eventName = $event.Name
        $eventHooks = $event.Value

        if (-not $existingConfig.hooks.$eventName) {
            $existingConfig.hooks.$eventName = @()
        }

        # 追加 hooks（避免重复）
        foreach ($hook in $eventHooks) {
            $hookJson = $hook | ConvertTo-Json -Depth 10
            $existing = $existingConfig.hooks.$eventName | ConvertTo-Json -Depth 10

            if ($existing -notmatch [regex]::Escape($hookJson)) {
                $existingConfig.hooks.$eventName += $hook
            }
        }
    }

    # 保存配置
    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    $existingConfig | ConvertTo-Json -Depth 10 | Out-File $ConfigPath -Encoding UTF8
    Write-Host "  已安装"
}

# 验证 OpenMemory 可达性
function Test-OpenMemory {
    param([string]$Endpoint)

    Write-Host "验证 OpenMemory 可达性..."

    try {
        $response = Invoke-RestMethod -Uri "$Endpoint/health" -Method Get -TimeoutSec 5 -ErrorAction Stop
        Write-Host "  OpenMemory 可达"
        return $true
    }
    catch {
        Write-Warning "  OpenMemory 不可达: $($_.Exception.Message)"
        return $false
    }
}

# 创建定时任务
function Register-SyncTask {
    param([int]$IntervalHours)

    Write-Host "创建定时同步任务..."

    $taskName = "MemoryBridge-Sync"
    $scriptPath = Join-Path $InstallDir "scripts\sync\collect.ps1"

    # 删除现有任务
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # 创建新任务
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-NoProfile -File `"$scriptPath`" `"$Config`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours $IntervalHours)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Memory Bridge 定期同步"

    Write-Host "  已创建定时任务: $taskName (每 $IntervalHours 小时)"
}

# 主逻辑
if ($Uninstall) {
    Write-Host "=== Memory Bridge 卸载 ==="

    foreach ($client in $config.clients) {
        $configPath = $ClientPaths[$client]
        if ($configPath) {
            Uninstall-Client -ClientName $client -ConfigPath $configPath
        }
    }

    # 删除定时任务
    Unregister-ScheduledTask -TaskName "MemoryBridge-Sync" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "已删除定时任务"

    Write-Host "=== 卸载完成 ==="
}
else {
    Write-Host "=== Memory Bridge 安装 ==="

    # 验证 OpenMemory
    if ($config.openmemory.endpoint) {
        $null = Test-OpenMemory -Endpoint $config.openmemory.endpoint
    }

    # 安装各客户端
    $installed = @()
    $skipped = @()

    foreach ($client in $config.clients) {
        $configPath = $ClientPaths[$client]

        if (-not $configPath) {
            Write-Warning "$client 配置路径待确认，跳过"
            $skipped += $client
            continue
        }

        Install-Client -ClientName $client -ConfigPath $configPath
        $installed += $client
    }

    # 创建定时任务
    if ($config.sync.enabled) {
        Register-SyncTask -IntervalHours $config.sync.interval_hours
    }

    # 输出报告
    Write-Host ""
    Write-Host "=== 安装报告 ==="
    Write-Host "已安装: $($installed.Count) 个客户端"
    if ($skipped.Count -gt 0) {
        Write-Host "已跳过: $($skipped -join ', ')"
    }
    Write-Host ""
    Write-Host "配置文件: $Config"
    Write-Host "备份目录: $BackupDir"
    Write-Host ""
    Write-Host "安装完成！"
}
