<p align="center"><img src="../Resources/AppIcon.png" width="144" alt="Claude Narrator 图标"></p>

# Claude Narrator

**Claude 做完，听它讲给你。**

一个原生 macOS 小工具：Claude Code 完成本轮任务后，自动把回答用语音讲给你听。你可以继续做手头的事情，不必一直盯着终端等结果。

默认保留 Claude 已经精简过的文字和顺序，不再挑选四句话、不再截断成 360 字摘要。清理 Markdown、代码块和网址，把长路径缩短成文件名，让文字更适合听。

- 四种中文自然神经音色，无法使用时回退到系统语音。
- 暂停、继续、停止、重播、静音和语速调节。
- 菜单栏控制与全局快捷键，可设置登录启动。
- 可选本机口语润色；需要 macOS 26 与可用的 Apple Intelligence。长回答或模型不可用时按清理后的原文播报。

## 下载试用

1. 在 [Releases](https://github.com/HarrisHan/claude-narrator/releases/tag/v0.1.1) 下载 `Claude-Narrator-macOS-arm64.zip` 并解压。
2. 将 App 移入“应用程序”后打开。早期版本仅做临时签名、尚未经过 Apple 公证；如被系统拦截，仅在信任此版本的前提下，到“系统设置 → 隐私与安全性”选择“仍要打开”。
3. 在终端运行 `python3 /解压目录/install-hook.py`（替换为实际路径），然后重启 Claude Code。
4. 让 Claude 完成一次回答，即可听到系统语音；自然音色按下方步骤另行安装。

下载包面向 Apple Silicon Mac；Intel 用户可尝试源码构建，尚未验证兼容性。Hook 安装仍需要 Python 3。

## 源码构建

需要 macOS 15+、Xcode 命令行工具（兼容 Swift 5.10+）、Python 3，以及支持 HTTP Stop Hook 和 `last_assistant_message` 的 Claude Code。当前音色主要面向中文。

在项目目录运行：

```sh
git clone https://github.com/HarrisHan/claude-narrator.git
cd claude-narrator
./scripts/build-app.sh
mkdir -p "$HOME/Applications"
ditto "dist/Claude Narrator.app" "$HOME/Applications/Claude Narrator.app"
open "$HOME/Applications/Claude Narrator.app"
python3 scripts/install-hook.py
```

安装器会备份 `~/.claude/settings.json`，添加本机 Hook，并替换旧的 `speak_last_reply.py` 播报项，保留其他 Hook。必要时重启 Claude Code 会话以加载配置。

可选安装自然语音组件：

```sh
python3 -m venv "$HOME/.claude/hooks/tts-venv"
"$HOME/.claude/hooks/tts-venv/bin/python" -m pip install edge-tts
```

未安装组件时使用 macOS 系统语音。当前提供早期下载包与源码构建，使用临时签名，尚未做 Apple 公证，兼容性目前只在开发者的 Mac 上验证。

## 隐私与数据

Hook 将回复传给本机 `127.0.0.1:17832`。格式清理与可选本机润色在本地进行。**开启自然神经语音时，播报文本通过 edge-tts 发送到微软在线语音服务**；关闭该开关即可使用系统语音。生成的音频会缓存在本机。App 不需要单独的 AI API Key。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌃⌥Space` | 暂停 / 继续 |
| `⌃⌥M` | 静音 |
| `⌃⌥S` | 停止 |
| `⌃⌥R` | 重播 |

运行测试：`swift test`。移除 Hook：`python3 scripts/uninstall-hook.py`。

独立项目，与 Anthropic 和 Microsoft 无隶属关系。

如果它让你的工作更轻松，欢迎点一个 Star 帮更多开发者发现它。安装问题、使用反馈和建议请提交到 [Issues](https://github.com/HarrisHan/claude-narrator/issues)。项目使用 [MIT 许可证](../LICENSE)。
