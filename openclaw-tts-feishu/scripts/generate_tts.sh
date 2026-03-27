#!/bin/bash
# MiMo TTS 通用语音合成脚本
# 用法: bash generate_tts.sh "文本内容" [风格标签] [voice] [provider]

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${SKILL_DIR}/config.json"

TEXT="${1:?用法: bash generate_tts.sh \"文本内容\" [风格标签] [voice] [provider]}"
STYLE="${2:-}"
VOICE="${3:-}"
PROVIDER="${4:-}"

# 读取配置
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 如果没指定provider，使用默认
if [ -z "$PROVIDER" ]; then
    PROVIDER=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['default_provider'])")
fi

# 从配置读取provider信息
read_config() {
    python3 -c "
import json, sys
c = json.load(open('$CONFIG_FILE'))
p = c['providers']['$PROVIDER']
print(p.get('$1', ''))
"
}

ENDPOINT=$(read_config "endpoint")
AUTH_HEADER=$(read_config "auth_header")
API_KEY=$(read_config "api_key")
MODEL=$(read_config "model")
DEFAULT_VOICE=$(read_config "default_voice")
FORMAT=$(read_config "format")
SUPPORTS_STYLE=$(read_config "supports_style")
OUTPUT_DIR=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['output_dir'])")
OUTPUT_WAV=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['output_wav'])")

# 默认值
if [ -z "$VOICE" ]; then
    VOICE="$DEFAULT_VOICE"
fi

# 构建带风格标签的文本
if [ -n "$STYLE" ] && [ "$SUPPORTS_STYLE" = "True" ]; then
    CONTENT="<style>${STYLE}</style>${TEXT}"
else
    CONTENT="${TEXT}"
fi

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

# 构建请求体（根据provider类型）
build_request_body() {
    local provider="$1"
    case "$provider" in
        mimo)
            cat <<EOF
{
    "model": "${MODEL}",
    "messages": [
        {"role": "user", "content": "请朗读"},
        {"role": "assistant", "content": "${CONTENT}"}
    ],
    "audio": {
        "format": "${FORMAT}",
        "voice": "${VOICE}"
    }
}
EOF
            ;;
        *)
            echo "ERROR: 不支持的provider: $provider"
            exit 1
            ;;
    esac
}

# 解析响应（根据provider类型）
parse_response() {
    local provider="$1"
    case "$provider" in
        mimo)
            python3 -c "
import sys, json, base64
try:
    d = json.load(sys.stdin)
    audio_data = d['choices'][0]['message']['audio']['data']
    wav = base64.b64decode(audio_data)
    with open('${OUTPUT_DIR}/${OUTPUT_WAV}', 'wb') as f:
        f.write(wav)
    print(f'OK: {len(wav)} bytes → ${OUTPUT_DIR}/${OUTPUT_WAV}')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
"
            ;;
        *)
            echo "ERROR: 不支持的provider: $provider"
            exit 1
            ;;
    esac
}

# 发送请求
BODY=$(build_request_body "$PROVIDER")
RESPONSE=$(curl -s -X POST "$ENDPOINT" \
  -H "${AUTH_HEADER}: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

# 解析并保存
echo "$RESPONSE" | parse_response "$PROVIDER"
