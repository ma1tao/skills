---
name: openclaw-tts-feishu
description: Convert text to speech and send as voice message on Feishu/Lark. Supports MiMo TTS with 7+ styles (开心/悲伤/东北话/台湾腔/四川话/粤语/悄悄话/唱歌). Auto-detects style from text context. Use when the user asks to send a voice message, speak text aloud, convert text to audio, or use TTS/语音合成. Trigger on "发语音"、"语音消息"、"朗读"、"念给我听"、"voice message"、"TTS".
---

# TTS 语音合成

将文本转为语音并发送飞书语音消息。

## 快速配置

### 第一步：获取 MiMo API Key

1. 访问 [小米 MiMo 开放平台](https://platform.xiaomimimo.com/)
2. 注册/登录账号
3. 进入「API 密钥管理」创建新密钥
4. 复制生成的 `sk-xxxxxxxx` 格式的 API Key

### 第二步：配置 config.json

编辑 `config.json`，将 `api_key` 替换为你自己的密钥：

```json
{
  "providers": {
    "mimo": {
      "api_key": "你的API_KEY粘贴到这里"
    }
  }
}
```

### 第三步：验证配置

```bash
bash scripts/generate_tts.sh "测试语音合成" "" && echo "✅ 配置成功"
```

如果输出 `OK: xxx bytes → ...` 说明配置正确。

---

## 扩展配置

**添加新TTS提供商：**
1. 在 `config.json` 的 `providers` 中新增一个条目
2. 在 `scripts/generate_tts.sh` 的 `build_request_body()` 和 `parse_response()` 中添加对应的case
3. 更新本SKILL.md的提供商文档

## 风格判断规则

**根据输入文本自动判断风格**，无需用户指定：

| 文本特征 | 自动选择风格 | 示例 |
|----------|-------------|------|
| 含"哈哈""笑死""太逗了"等 | 开心 | "哈哈哈你太搞笑了" → 开心 |
| 含"难过""可惜""遗憾"等 | 悲伤 | "好可惜啊" → 悲伤 |
| 含"！""!!!""太棒了"等 | 开心 | "成功了！！！" → 开心 |
| 含东北口音词（"嘎哈""整""呗"）| 东北话 | "这事儿整的呗" | 东北话 |
| 含四川词（"巴适""安逸""爪子"）| 四川话 | "要得嘛" | 四川话 |
| 含粤语词（"咩""唔""嘅"）| 粤语 | "唔好意思" | 粤语 |
| 含台湾腔词（"啦""喔""捏"）| 台湾腔 | "好啦好啦" | 台湾腔 |
| 含"悄悄说""小声""别让人听到" | 悄悄话 | "悄悄告诉你个秘密" | 悄悄话 |
| 含歌词/韵律/押韵 | 唱歌 | "一闪一闪亮晶晶" | 唱歌 |
| 用户明确指定风格 | 用户指定 | "用东北话发条语音" | 东北话 |
| 其他普通文本 | 无（默认音色） | "今天天气不错" | 无 |

**原则**：用户明确指定 > 自动判断 > 默认无风格

## 调用流程（三步走）

### Step 1: 生成音频

```bash
bash <skill_dir>/scripts/generate_tts.sh "文本内容" [风格标签] [voice] [provider]
```

参数：
- `文本内容`（必填）
- `风格标签`（可选，默认无）
- `voice`（可选，从config读默认值）
- `provider`（可选，默认使用 config.json 中的 default_provider）

输出：`/tmp/openclaw/tts-output.wav`

### Step 2: 转 opus 格式

飞书语音条必须 opus 格式：

```bash
bash <skill_dir>/scripts/tts_convert.sh [input_wav] [output_opus] [bitrate]
```

全部参数可选，默认从 config.json 读取。

输出：`/tmp/openclaw/tts-output.opus`

### Step 3: 发送语音消息

```
message(action=send, channel=feishu, media="/tmp/openclaw/tts-output.opus", asVoice=true)
```

## 完整示例

用户说"用台湾腔说晚安"：

```bash
# Step 1
bash <skill_dir>/scripts/generate_tts.sh "晚安，好好休息哦" "台湾腔"

# Step 2
bash <skill_dir>/scripts/tts_convert.sh

# Step 3
message(action=send, channel=feishu, media="/tmp/openclaw/tts-output.opus", asVoice=true)
```

## 注意事项
- 飞书语音条必须 **opus** 格式，wav会变成文件附件
- 文件存到 `/tmp/openclaw/` 目录
- 修改 api_key 只需编辑 `config.json`
- 添加新TTS提供商见上方"配置"章节
