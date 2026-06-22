# 测试 YAML 解析函数（修复注释处理版本）
$Config = "D:\Users\Lxx\SynologyDrive\Projects\AI-WorkSpace\memory-bridge\config.yaml"

# YAML 解析函数（手动解析，避免依赖 powershell-yaml 模块）
function Parse-YamlConfig {
    param([string]$YamlContent)

    $result = @{}
    $result.openmemory = @{}
    $result.hooks = @{}
    $result.sync = @{}
    $result.clients = @()

    $lines = $YamlContent -split "`n"
    $currentSection = ""
    $inClients = $false

    foreach ($line in $lines) {
        # 跳过注释和空行
        $trimmed = $line.Trim()
        if ($trimmed -match "^#" -or $trimmed -eq "") {
            continue
        }

        # 检测顶级 section
        if ($line -match "^openmemory:") {
            $currentSection = "openmemory"
            $inClients = $false
            continue
        }
        elseif ($line -match "^hooks:") {
            $currentSection = "hooks"
            $inClients = $false
            continue
        }
        elseif ($line -match "^sync:") {
            $currentSection = "sync"
            $inClients = $false
            continue
        }
        elseif ($line -match "^clients:") {
            $currentSection = "clients"
            $inClients = $true
            continue
        }

        # 解析 clients 列表
        if ($inClients -and $trimmed -match "^-\s+(.+)$") {
            $client = $Matches[1].Trim()
            $result.clients += $client
            continue
        }

        # 解析 key-value 对（移除行内注释）
        if ($trimmed -match "^([^:]+):\s*(.*?)\s*(#.*)?$") {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()

            # 移除引号
            if ($value -match "^`"(.*)`"$") {
                $value = $Matches[1]
            }

            # 转换布尔值
            if ($value -eq "true") { $value = $true }
            elseif ($value -eq "false") { $value = $false }

            # 转换数字
            if ($value -match "^\d+$") {
                $value = [int]$value
            }

            # 存储到对应 section
            switch ($currentSection) {
                "openmemory" { $result.openmemory[$key] = $value }
                "hooks" { $result.hooks[$key] = $value }
                "sync" { $result.sync[$key] = $value }
            }
        }
    }

    return $result
}

# 读取配置
Write-Host "读取配置: $Config"
$yamlContent = Get-Content $Config -Raw -Encoding UTF8
$config = Parse-YamlConfig -YamlContent $yamlContent

# 输出解析结果
Write-Host "`n=== 解析结果 ==="
Write-Host "openmemory.endpoint: $($config.openmemory.endpoint)"
Write-Host "openmemory.api_key: '$($config.openmemory.api_key)'"
Write-Host "openmemory.user_id: $($config.openmemory.user_id)"
Write-Host "openmemory.api_prefix: $($config.openmemory.api_prefix)"
Write-Host "`nhooks.on_session_start: $($config.hooks.on_session_start)"
Write-Host "hooks.on_stop: $($config.hooks.on_stop)"
Write-Host "hooks.on_prompt_submit: $($config.hooks.on_prompt_submit)"
Write-Host "`nsync.enabled: $($config.sync.enabled)"
Write-Host "sync.interval_hours: $($config.sync.interval_hours)"
Write-Host "`nclients: $($config.clients -join ', ')"
Write-Host "clients count: $($config.clients.Count)"

# 验证 workbuddy 是否在列表中
if ($config.clients -contains "workbuddy") {
    Write-Host "`n✓ workbuddy 已成功添加到客户端列表"
} else {
    Write-Host "`n✗ workbuddy 未找到"
}
