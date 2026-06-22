#!/usr/bin/env python3
"""
Memory Bridge - 会话结束时保存记忆到 OpenMemory

读取 transcript 提取关键信息，写入 OpenMemory。
超时 10 秒，失败不影响客户端正常退出。

stdin: JSON (transcript_path, session_id, last_assistant_message 等)
stdout: 无输出（或空 JSON）
"""

import sys
import json
import os
import urllib.request
import urllib.error
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
        
        # 检查 stop_hook_active（防递归机制）
        if input_data.get('stop_hook_active') == True:
            exit_safely()
        
        # 获取配置路径
        config_path = os.environ.get('MEMORY_BRIDGE_CONFIG')
        if not config_path:
            # 尝试从脚本目录查找
            script_dir = os.path.dirname(os.path.abspath(__file__))
            config_path = os.path.join(script_dir, '..', '..', 'config.yaml')
        
        if not os.path.exists(config_path):
            exit_safely()
        
        # 读取配置
        config = parse_yaml_config(config_path)
        if not config or 'openmemory' not in config:
            exit_safely()
        
        endpoint = config['openmemory'].get('endpoint')
        api_key = config['openmemory'].get('api_key')
        user_id = config['openmemory'].get('user_id')
        
        if not endpoint:
            exit_safely()
        
        # 获取对话内容
        transcript = ""
        
        # 优先使用 last_assistant_message
        if input_data.get('last_assistant_message'):
            transcript = input_data['last_assistant_message']
        # 其次尝试读取 transcript_path
        elif input_data.get('transcript_path'):
            transcript_path = input_data['transcript_path']
            if os.path.exists(transcript_path):
                try:
                    with open(transcript_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if content:
                            # 只取最后 2000 字符
                            if len(content) > 2000:
                                transcript = content[-2000:]
                            else:
                                transcript = content
                except:
                    pass
        
        if not transcript or not transcript.strip():
            exit_safely()
        
        # 构建 messages 数组
        messages = [
            {
                'role': 'assistant',
                'content': transcript
            }
        ]
        
        # 构建请求
        headers = {
            'Content-Type': 'application/json'
        }
        if api_key:
            headers['Authorization'] = f'Bearer {api_key}'
        
        body = json.dumps({
            'messages': messages,
            'user_id': user_id
        }).encode('utf-8')
        
        # 调用 OpenMemory memories API
        try:
            req = urllib.request.Request(
                f'{endpoint}/memories',
                data=body,
                headers=headers,
                method='POST'
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                pass
        except:
            pass
        
        # 成功或失败都静默退出
        exit_safely()
        
    except:
        exit_safely()

if __name__ == '__main__':
    main()
