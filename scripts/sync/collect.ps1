<#
.SYNOPSIS
    Memory Bridge - 定期收集各客户端本地记忆文件

.DESCRIPTION
    扫描各客户端本地记忆文件，增量同步到 OpenMemory。

.PARAMETER ConfigPath
    config.yaml 的路径（可选）

.NOTES
    用于定时任务或手动执行
#>

param(
    [string]$ConfigPath
)

# 强制使用 UTF-8 输出
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 静默退出函数
function Exit-Safely {
    exit 0
}

# 展开路径（支持 ~ 和通配符）
function Expand-SourcePath {
    param([string]$Path)

    # 替换 ~ 为用户目录
    $expandedPath = $Path -replace '^~', $env:USERPROFILE

    # 处理通配符
    if ($expandedPath -match '\*') {
        return (Resolve-Path $expandedPath -ErrorAction SilentlyContinue)
    }

    return $expandedPath
}

# 获取 last_sync 时间戳文件路径
function Get-SyncStatePath {
    return Join-Path $env:USERPROFILE ".memory-bridge\last_sync.json"
}

# 读取 last_sync 状态
function Get-SyncState {
    $statePath = Get-SyncStatePath
    if (Test-Path $statePath) {
        return Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return @{}
}

# 保存 last_sync 状态
function Save-SyncState {
    param($State)

    $statePath = Get-SyncStatePath
    $stateDir = Split-Path $statePath -Parent

    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    }

    $State | ConvertTo-Json -Depth 10 | Out-File $statePath -Encoding UTF8
}

try {
    # 获取配置路径
    if (-not $ConfigPath) {
        $ConfigPath = $env:MEMORY_BRIDGE_CONFIG
    }
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot "..\..\config.yaml"
    }
    $ConfigPath = Resolve-Path $ConfigPath -ErrorAction SilentlyContinue
    if (-not $ConfigPath) {
        Write-Host "配置文件未找到"
        Exit-Safely
    }

    # 读取配置
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Yaml -ErrorAction SilentlyContinue
    if (-not $config -or -not $config.openmemory) {
        Write-Host "配置无效"
        Exit-Safely
    }

    # 检查 sync 是否启用
    if (-not $config.sync -or -not $config.sync.enabled) {
        Write-Host "同步未启用"
        Exit-Safely
    }

    $endpoint = $config.openmemory.endpoint
    $apiKey = $config.openmemory.api_key
    $userId = $config.openmemory.user_id
    $sources = $config.sync.sources

    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        Write-Host "OpenMemory endpoint 未配置"
        Exit-Safely
    }

    # 读取同步状态
    $syncState = Get-SyncState

    # 构建请求头
    $headers = @{
        "Content-Type" = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $headers["Authorization"] = "Bearer $apiKey"
    }

    $totalSynced = 0

    # 遍历每个源
    foreach ($source in $sources.PSObject.Properties) {
        $sourceName = $source.Name
        $sourcePath = $source.Value

        Write-Host "处理源: $sourceName"

        # 展开路径
        $expandedPaths = Expand-SourcePath $sourcePath

        if (-not $expandedPaths) {
            Write-Host "  路径未找到: $sourcePath"
            continue
        }

        # 处理多个路径（通配符展开）
        $paths = @($expandedPaths)

        foreach ($path in $paths) {
            # 检查是文件还是目录
            if (Test-Path $path -PathType Leaf) {
                # 单个文件
                $files = @(Get-Item $path)
            } else {
                # 目录，获取 .md 文件
                $files = Get-ChildItem -Path $path -Filter "*.md" -File -ErrorAction SilentlyContinue
            }

            if (-not $files -or $files.Count -eq 0) {
                Write-Host "  无 .md 文件"
                continue
            }

            # 获取上次同步时间
            $lastSync = $null
            if ($syncState.$sourceName) {
                $lastSync = [DateTime]::Parse($syncState.$sourceName)
            }

            # 过滤新增/修改的文件
            $filesToSync = $files | Where-Object {
                if (-not $lastSync) { return $true }
                return $_.LastWriteTime -gt $lastSync
            }

            if (-not $filesToSync -or $filesToSync.Count -eq 0) {
                Write-Host "  无新文件需要同步"
                continue
            }

            Write-Host "  同步 $($filesToSync.Count) 个文件"

            # 同步每个文件
            foreach ($file in $filesToSync) {
                $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ([string]::IsNullOrWhiteSpace($content)) { continue }

                # 构建 messages
                $messages = @(
                    @{
                        role = "user"
                        content = "File: $($file.Name)`n$content"
                    }
                )

                $body = @{
                    messages = $messages
                    user_id = $userId
                    metadata = @{
                        source = $sourceName
                        file = $file.Name
                        synced_at = (Get-Date).ToString("o")
                    }
                } | ConvertTo-Json -Depth 10

                # 调用 OpenMemory API
                try {
                    $null = Invoke-RestMethod `
                        -Uri "$endpoint/memories" `
                        -Method Post `
                        -Headers $headers `
                        -Body $body `
                        -TimeoutSec 10 `
                        -ErrorAction Stop

                    $totalSynced++
                    Write-Host "    已同步: $($file.Name)"
                }
                catch {
                    Write-Host "    同步失败: $($file.Name) - $($_.Exception.Message)"
                }
            }
        }

        # 更新同步状态
        $syncState.$sourceName = (Get-Date).ToString("o")
    }

    # 保存同步状态
    Save-SyncState $syncState

    Write-Host "同步完成: 共 $totalSynced 个文件"
    exit 0
}
catch {
    Write-Host "同步出错: $($_.Exception.Message)"
    Exit-Safely
}
