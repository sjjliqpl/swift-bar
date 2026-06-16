# SwiftBar 插件

[English README](README.md)

这是一组 macOS [SwiftBar](https://swiftbar.app/) 菜单栏插件，用来查看网速、CPU、内存和账户余额。

## 插件列表

| 脚本 | 刷新频率 | 说明 |
| --- | ---: | --- |
| `swift bar/network-speed.2s.sh` | 2 秒 | 菜单栏显示当前下载速度，下拉菜单显示上传速度和网络详情。 |
| `swift bar/cpu-usage.2s.sh` | 2 秒 | 显示总体 CPU 占用和占用最高的应用。 |
| `swift bar/memory-usage.2s.sh` | 2 秒 | 显示估算的 App 内存占用、内存明细和 Swap 用量。 |
| `swift bar/nf-video-balance.5m.sh` | 5 分钟 | 显示 NF Video/OpenAI 仪表盘余额。需要 `NF_VIDEO_COOKIE`。 |
| `swift bar/deepseek-balance.1h.sh` | 1 小时 | 显示 DeepSeek 余额和 Token 估算。需要 `DEEPSEEK_TOKEN`。 |

## 依赖

- macOS
- [SwiftBar](https://swiftbar.app/)
- Bash 和 macOS 自带命令行工具
- 余额插件需要 `jq`

如果没有 `jq`，可以用 Homebrew 安装：

```bash
brew install jq
```

## 安装

1. 克隆这个仓库。
2. 打开 SwiftBar，把 `swift bar` 目录设置为插件目录；或者把需要的脚本复制到你现有的 SwiftBar 插件目录。
3. 确认脚本有执行权限：

```bash
chmod +x "swift bar"/*.sh
```

## 隐私配置

脚本里不保存敏感信息。余额插件会先读取 `swift bar` 插件目录里的私有 `.env` 文件，再回退到系统环境变量。

| 环境变量 | 使用脚本 |
| --- | --- |
| `NF_VIDEO_COOKIE` | `swift bar/nf-video-balance.5m.sh` |
| `DEEPSEEK_TOKEN` | `swift bar/deepseek-balance.1h.sh` |

创建私有配置文件：

```bash
cp "swift bar/.env.example" "swift bar/.env"
```

然后编辑 `swift bar/.env`：

```bash
NF_VIDEO_COOKIE='你的 cookie'
DEEPSEEK_TOKEN='你的 token'
```

编辑后退出并重新打开 SwiftBar。`.env` 文件已被 Git 忽略。

## 说明

- 错误信息会写入 `/tmp/swiftbar-*.err`，每个插件下拉菜单里有打开错误日志的入口。
- 网速插件会在 `/tmp/swiftbar-network-speed.state` 保存一次短暂状态，用来计算速率。
- 余额接口可能变化，凭据也可能过期；出错时更新对应环境变量即可。

## 许可证

MIT
