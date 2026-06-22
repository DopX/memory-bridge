#!/usr/bin/env python3
"""
Memory Bridge - prompt 前注入记忆提醒

在 UserPromptSubmit 时注入一行提醒，提示 AI 使用 memory 工具。

stdin: JSON
stdout: JSON (reminder)
"""

import sys
import json
import os
import re

def exit_safely():
    sys.exit(0)

def parse_yaml_config(config_path):
    """简单解析 YAML 配置文件（仅支持 memory-bridge 的配置格式）"""
    config = {"openmemory": {}, "hooks": {}}
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except:
        return None
    
    current_section = None
    in_clients = False
    
    for line in content.split('\n'):
        stripped = line.strip()
        
        # 跳过注释和空行
        if stripped.startswith('#') or stripped == '':
            continue
        
        # 检测顶级 section
        if line.startswith('openmemory:'):
            current_section = 'openmemory'
            in_clients = False
            continue
        elif line.startswith('hooks:'):
            current_section = 'hooks'
            in_clients = False
            continue
        elif line.startswith('sync:'):
            current_section = 'sync'
            in_clients = False
            continue
        elif line.startswith('clients:'):
            current_section = 'clients'
            in_clients = True
            continue
        
        # 解析 clients 列表
        if in_clients and stripped.startswith('- '):
            client = stripped[2:].strip()
            if 'clients' not in config:
                config['clients'] = []
            config['clients'].append(client)
            continue
        
        # 解析 key-value 对
        match = re.match(r'^([^:]+):\s*(.*)$', stripped)
        if match and current_section:
            key = match.group(1).strip()
            value = match.group(2).strip()
            
            # 移除引号
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            
            # 转换布尔值
            if value == 'true':
                value = True
            elif value == 'false':
                value = False
            # 转换数字
            elif value.isdigit():
                value = int(value)
            
            # 存储到对应 section
            if current_section == 'openmemory':
                config['openmemory'][key] = value
            elif current_section == 'hooks':
                config['hooks'][key] = value
    
    return config

def main():
    try:
        # 读取 stdin JSON
        stdin_content = sys.stdin.read()
        if not stdin_content or not stdin_content.strip():
            exit_safely()
        
        try:
            input_data = json.loads(stdin_content)
        except:
            exit_safely()
        
        # 获取配置路径
        config_path = os.environ.get('MEMORY_BRIDGE_CONFIG')
        if not config_path:
            # 尝试从脚本目录查找
            script_dir = os.path.dirname(os.path.abspath(__file__))
            config_path = os.path.join(script_dir, '..', '..', 'config.yaml')
        
        if not os.path.exists(config_path):
            exit_safely()
        
        # 读取配置检查是否启用
        config = parse_yaml_config(config_path)
        if not config or 'hooks' not in config:
            exit_safely()
        
        # 检查 on_prompt_submit 是否启用
        if not config['hooks'].get('on_prompt_submit'):
            exit_safely()
        
        # 输出提醒 JSON
        output = {
            'additionalContext': {
                'type': 'reminder',
                'content': '提示：如果需要回忆之前的对话或项目细节，请使用 memory 工具搜索相关记忆。'
            }
        }
        print(json.dumps(output, ensure_ascii=False))
        sys.exit(0)
        
    except:
        exit_safely()

if __name__ == '__main__':
    main()
