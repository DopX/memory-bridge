<#
.SYNOPSIS
    Memory Bridge - 会话开始时从 OpenMemory 检索相关记忆

.DESCRIPTION
    从 OpenMemory 搜索与当前项目/会话相关的记忆，输出到 stdout 供 hooks 注入。
    必须处理 OpenMemory 不可达的情况（超时 5 秒，失败静默退出码 0）

.PARAMETER ConfigPath
    config.yaml 的路径（可选，默认从环境变量或脚本目录上级查找）

.NOTES
    stdin: JSON (session_id, cwd, hook_event_name 等)
    stdout: JSON (additionalContext) 或为空
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

try {
    # 读取 stdin JSON
    $stdinContent = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($stdinContent)) {
        Exit-Safely
    }

    $inputData = $stdinContent | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $inputData) {
        Exit-Safely
    }

    # 获取配置路径
    if (-not $ConfigPath) {
        $ConfigPath = $env:MEMORY_BRIDGE_CONFIG
    }
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot "..\..\config.yaml"
    }
    $ConfigPath = Resolve-Path $ConfigPath -ErrorAction SilentlyContinue
    if (-not $ConfigPath) {
        Exit-Safely
    }

    # 读取配置
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Yaml -ErrorAction SilentlyContinue
    if (-not $config -or -not $config.openmemory) {
        Exit-Safely
    }

    $endpoint = $config.openmemory.endpoint
    $apiKey = $config.openmemory.api_key
    $userId = $config.openmemory.user_id

    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        Exit-Safely
    }

    # 构建查询：使用 cwd 的项目名
    $query = ""
    if ($inputData.cwd) {
        $query = Split-Path $inputData.cwd -Leaf
    }
    if ([string]::IsNullOrWhiteSpace($query)) {
        $query = "general"
    }

    # 构建请求
    $headers = @{
        "Content-Type" = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $headers["Authorization"] = "Bearer $apiKey"
    }

    $body = @{
        query = $query
        user_id = $userId
    } | ConvertTo-Json -Depth 10

    # 调用 OpenMemory search API
    $response = Invoke-RestMethod `
        -Uri "$endpoint/search" `
        -Method Post `
        -Headers $headers `
        -Body $body `
        -TimeoutSec 5 `
        -ErrorAction SilentlyContinue

    if (-not $response -or -not $response.memories) {
        Exit-Safely
    }

    # 格式化记忆为简洁文本
    $memories = $response.memories
    if ($memories.Count -eq 0) {
        Exit-Safely
    }

    $memoryText = $memories | ForEach-Object {
        "- $($_.text)"
    } | Join-String -Separator "`n"

    # 输出 JSON（符合 additionalContext 格式）
    $output = @{
        additionalContext = @{
            type = "memory"
            content = $memoryText
        }
    } | ConvertTo-Json -Depth 10

    Write-Output $output
    exit 0
}
catch {
    # 任何异常都静默退出
    Exit-Safely
}
