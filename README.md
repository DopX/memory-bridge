# Memory Bridge

将多个 AI 客户端的记忆系统桥接到统一的 OpenMemory 后端。

## 安装

```powershell
.\install.ps1
```

或指定配置文件：

```powershell
.\install.ps1 -Config "D:\path\to\config.yaml"
```

## 支持的客户端

| 客户端 | 状态 | 配置路径 |
|--------|------|----------|
| Claude Code | Stable | `~/.claude/settings.json` |
| Qoder | Stable | `~/.qoder/settings.json` |
| CodeBuddy | Stable | `~/.codebuddy/settings.json` |
| Cursor | Stable | `~/.cursor/hooks.json` |
| Codex CLI | Stable | `~/.codex/hooks.json` |
| Windsurf | Stable | `~/.codeium/windsurf/hooks.json` |
| Gemini CLI | Stable | `~/.gemini/settings.json` |
| Trae | Experimental | 待确认 |
| GitHub Copilot | Experimental | VS Code 插件机制 |

## 配置说明

编辑 `config.yaml`：

```yaml
openmemory:
  endpoint: "http://your-openmemory-server:8888"
  api_key: ""  # 留空则不使用认证
  user_id: "your-user-id"

hooks:
  on_session_start: true   # 会话开始时检索记忆
  on_stop: true            # 会话结束时保存记忆
  on_prompt_submit: false  # prompt 前注入提醒（默认关闭）

sync:
  enabled: true
  interval_hours: 6
  sources:
    claude_code: "~/.claude/projects/*/memory/"
    codex: "~/.codex/memories/"
    gemini: "~/.gemini/GEMINI.md"

clients:
  - claude-code
  - qoder
  - codebuddy
  - cursor
  - codex
  - windsurf
  - gemini
```

## 工作原理

1. **recall.ps1** - 会话开始时从 OpenMemory 搜索相关记忆，注入到 AI 上下文
2. **save.ps1** - 会话结束时提取关键对话，保存到 OpenMemory
3. **remind.ps1** - prompt 前注入提醒（可选）
4. **collect.ps1** - 定期收集各客户端本地记忆文件，同步到 OpenMemory

## 卸载

```powershell
.\install.ps1 -Uninstall
```

卸载会恢复所有备份的配置文件。

## 目录结构

```
memory-bridge/
├── config.yaml           # 主配置文件
├── install.ps1           # 安装/卸载脚本
├── scripts/
│   ├── hooks/
│   │   ├── recall.ps1    # 会话开始时检索记忆
│   │   ├── save.ps1      # 会话结束时保存记忆
│   │   └── remind.ps1    # prompt 前注入提醒
│   └── sync/
│       └── collect.ps1   # 定期收集本地记忆
├── clients/              # 各客户端配置模板
│   ├── claude-code.json
│   ├── qoder.json
│   ├── codebuddy.json
│   ├── cursor.json
│   ├── codex.json
│   ├── windsurf.json
│   ├── gemini.json
│   ├── trae.json
│   └── copilot.json
└── README.md
```

## 备份

安装时会自动备份现有配置到 `~/.memory-bridge/backups/`。

## 注意事项

- 所有脚本失败不会阻塞客户端（退出码 0）
- OpenMemory 不可达时静默降级
- 需要 PowerShell 7+
- 超时设置：recall 5 秒，save 10 秒
