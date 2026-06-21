<#
.SYNOPSIS
    Memory Bridge - prompt 前注入记忆提醒

.DESCRIPTION
    在 UserPromptSubmit 时注入一行提醒，提示 AI 使用 memory 工具。

.PARAMETER ConfigPath
    config.yaml 的路径（可选）

.NOTES
    stdin: JSON
    stdout: JSON (reminder)
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

    # 读取配置检查是否启用
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Yaml -ErrorAction SilentlyContinue
    if (-not $config -or -not $config.hooks) {
        Exit-Safely
    }

    # 检查 on_prompt_submit 是否启用
    if (-not $config.hooks.on_prompt_submit) {
        Exit-Safely
    }

    # 输出提醒 JSON
    $output = @{
        additionalContext = @{
            type = "reminder"
            content = "提示：如果需要回忆之前的对话或项目细节，请使用 memory 工具搜索相关记忆。"
        }
    } | ConvertTo-Json -Depth 10

    Write-Output $output
    exit 0
}
catch {
    # 任何异常都静默退出
    Exit-Safely
}
