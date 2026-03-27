#!/bin/bash
# TTS 格式转换脚本（wav → opus）
# 用法: bash tts_convert.sh [input_wav] [output_opus] [bitrate]

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${SKILL_DIR}/config.json"

OUTPUT_DIR=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['output_dir'])")
OUTPUT_WAV=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['output_wav'])")
OUTPUT_OPUS=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['output_opus'])")
OPUS_BITRATE=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c['opus_bitrate'])")

INPUT="${1:-${OUTPUT_DIR}/${OUTPUT_WAV}}"
OUTPUT="${2:-${OUTPUT_DIR}/${OUTPUT_OPUS}}"
BITRATE="${3:-${OPUS_BITRATE}}"

if [ ! -f "$INPUT" ]; then
    echo "ERROR: 输入文件不存在: $INPUT"
    exit 1
fi

ffmpeg -y -i "$INPUT" -c:a libopus -b:a "$BITRATE" "$OUTPUT" 2>&1 | tail -1
if [ $? -eq 0 ]; then
    SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT")
    echo "OK: ${SIZE} bytes → ${OUTPUT}"
else
    echo "ERROR: 转换失败"
    exit 1
fi
