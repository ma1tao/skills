# MiMo TTS 使用示例

## 基础用例

### 1. 普通语音
```bash
bash scripts/generate_tts.sh "今天天气真不错"
bash scripts/tts_convert.sh
# → message(asVoice=true, media="/tmp/openclaw/tts-output.opus")
```

### 2. 带情感
```bash
bash scripts/generate_tts.sh "太棒了！我们成功了！" "开心"
```

### 3. 方言风格
```bash
bash scripts/generate_tts.sh "哎呀妈呀，这也太厉害了吧" "东北话"
```

### 4. 台湾腔
```bash
bash scripts/generate_tts.sh "晚安啦，要早点休息哦" "台湾腔"
```

### 5. 唱歌
```bash
bash scripts/generate_tts.sh "小星星 亮晶晶 满天都是小星星" "唱歌"
```

### 6. 指定音色
```bash
bash scripts/generate_tts.sh "Hello world" "" "default_en"
```

## 进阶用例

### 指定不同provider（未来扩展）
```bash
bash scripts/generate_tts.sh "测试文本" "" "" "baidu"
```

### 自定义输出路径
```bash
bash scripts/tts_convert.sh /tmp/openclaw/tts-output.wav /tmp/openclaw/custom.opus 48k
