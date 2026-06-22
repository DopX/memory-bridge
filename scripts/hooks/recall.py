#!/usr/bin/env python3
"""
Memory Bridge - 会话开始时从 OpenMemory 检索相关记忆

从 OpenMemory 搜索与当前项目/会话相关的记忆，输出到 stdout 供 hooks 注入。
必须处理 OpenMemory 不可达的情况（超时 5 秒，失败静默退出码 0）

stdin: JSON (session_id, cwd, hook_event_name 等)
stdout: JSON (additionalContext) 或为空
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
        
        # 构建查询：使用 cwd 的项目名
        query = "general"
        if 'cwd' in input_data and input_data['cwd']:
            query = os.path.basename(input_data['cwd'])
        
        # 构建请求
        headers = {
            'Content-Type': 'application/json'
        }
        if api_key:
            headers['Authorization'] = f'Bearer {api_key}'
        
        body = json.dumps({
            'query': query,
            'user_id': user_id
        }).encode('utf-8')
        
        # 调用 OpenMemory search API
        try:
            req = urllib.request.Request(
                f'{endpoint}/search',
                data=body,
                headers=headers,
                method='POST'
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                response_data = json.loads(response.read().decode('utf-8'))
        except:
            exit_safely()
        
        if not response_data or 'memories' not in response_data:
            exit_safely()
        
        memories = response_data['memories']
        if not memories:
            exit_safely()
        
        # 格式化记忆为简洁文本
        memory_text = '\n'.join([f'- {m.get("text", "")}' for m in memories])
        
        # 输出 JSON（符合 additionalContext 格式）
        output = {
            'additionalContext': {
                'type': 'memory',
                'content': memory_text
            }
        }
        print(json.dumps(output, ensure_ascii=False))
        sys.exit(0)
        
    except:
        exit_safely()

if __name__ == '__main__':
    main()
