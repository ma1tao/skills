# Skills 技能库

欢迎使用 **Skills** 技能库。这是一个集成多种自动化和生产力工具的技能集合。

## 🚀 现有技能列表

| 技能名称 | 描述 | 入口文件 |
|----------|------|---------|
| [openclaw-tts-feishu](./openclaw-tts-feishu/SKILL.md) | 将文本转换为语音并发送到飞书（目前支持 MiMo TTS 和多种方言风格） | `openclaw-tts-feishu/SKILL.md` |
| [gongwenformat-pro](./gongwenformat-pro/SKILL.md) | 党政机关公文标准排版 Pro（GB/T 9704-2012）：将 Markdown/文本转为国标排版的 Word（.docx） | `gongwenformat-pro/SKILL.md` |

---

## 🛠️ 如何使用

每个技能都在其子目录中包含详细的说明文档。请点击上方表格中的链接或进入对应目录查看具体的配置和使用指南。

通用流程：
1. 打开对应技能的 `SKILL.md`
2. 按文档要求完成配置（例如 `config.json`、API Key、依赖环境等）
3. 运行技能目录下的脚本进行验证（如果提供了 `scripts/`）
4. 将输出结果按你的工作流使用（例如发送到飞书、生成文件并回传等）

---

## ➕ 如何添加新技能

如果你想贡献一个新技能，请遵循以下步骤：

1. **创建子目录**：在根目录下创建一个描述性的文件夹（例如 `my-new-skill`）。
2. **编写文档**：创建一个 `SKILL.md` 文件，描述技能的名称、功能、配置方法和调用流程。
3. **添加代码**：将相关的脚本或源码放入该文件夹（推荐使用 `scripts` 子文件夹存放执行脚本）。
4. **更新 README**：在根目录的 `README.md` 中添加你的技能条目。

---

## 📁 目录结构约定

建议每个技能遵循以下结构（按需提供）：
- `<skill-name>/SKILL.md`：技能说明与调用方式
- `<skill-name>/config.json`：配置示例（如需）
- `<skill-name>/scripts/`：脚本入口与工具（如需）
- `<skill-name>/assets/`：示例、素材与截图（如需）
