<#
.SYNOPSIS
    Memory Bridge - 会话结束时保存记忆到 OpenMemory

.DESCRIPTION
    读取 transcript 提取关键信息，写入 OpenMemory。
    超时 10 秒，失败不影响客户端正常退出。

.PARAMETER ConfigPath
    config.yaml 的路径（可选）

.NOTES
    stdin: JSON (transcript_path, session_id, last_assistant_message 等)
    stdout: 无输出（或空 JSON）
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

    # 检查 stop_hook_active（防递归机制）
    if ($inputData.stop_hook_active -eq $true) {
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

    # 获取对话内容
    $transcript = ""

    # 优先使用 last_assistant_message
    if ($inputData.last_assistant_message) {
        $transcript = $inputData.last_assistant_message
    }
    # 其次尝试读取 transcript_path
    elseif ($inputData.transcript_path) {
        $transcriptPath = $inputData.transcript_path
        if (Test-Path $transcriptPath) {
            $content = Get-Content $transcriptPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($content) {
                # 只取最后 2000 字符
                if ($content.Length -gt 2000) {
                    $transcript = $content.Substring($content.Length - 2000)
                } else {
                    $transcript = $content
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($transcript)) {
        Exit-Safely
    }

    # 构建 messages 数组
    $messages = @(
        @{
            role = "assistant"
            content = $transcript
        }
    )

    # 构建请求
    $headers = @{
        "Content-Type" = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $headers["Authorization"] = "Bearer $apiKey"
    }

    $body = @{
        messages = $messages
        user_id = $userId
    } | ConvertTo-Json -Depth 10

    # 调用 OpenMemory memories API
    $null = Invoke-RestMethod `
        -Uri "$endpoint/memories" `
        -Method Post `
        -Headers $headers `
        -Body $body `
        -TimeoutSec 10 `
        -ErrorAction SilentlyContinue

    # 成功或失败都静默退出
    Exit-Safely
}
catch {
    # 任何异常都静默退出
    Exit-Safely
}
