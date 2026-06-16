# SwiftBar Plugins

[中文说明](README.zh-CN.md)

A small collection of macOS [SwiftBar](https://swiftbar.app/) plugins for monitoring network speed, CPU usage, memory usage, and account balances from the menu bar.

## Plugins

| Script | Refresh | Description |
| --- | ---: | --- |
| `swift bar/network-speed.2s.sh` | 2s | Shows current download speed in the menu bar and upload/network details in the dropdown. |
| `swift bar/cpu-usage.2s.sh` | 2s | Shows total CPU usage and the top CPU-consuming applications. |
| `swift bar/memory-usage.2s.sh` | 2s | Shows estimated app memory usage, memory breakdown, and swap usage. |
| `swift bar/nf-video-balance.5m.sh` | 5m | Shows NF Video/OpenAI dashboard balance. Requires `NF_VIDEO_COOKIE`. |
| `swift bar/deepseek-balance.1h.sh` | 1h | Shows DeepSeek balance and token estimates. Requires `DEEPSEEK_TOKEN`. |

## Requirements

- macOS
- [SwiftBar](https://swiftbar.app/)
- Bash and standard macOS command-line tools
- `jq` for the balance plugins

Install `jq` with Homebrew if needed:

```bash
brew install jq
```

## Installation

1. Clone this repository.
2. Open SwiftBar and select the `swift bar` directory as the plugin folder, or copy the scripts you need into your existing SwiftBar plugin folder.
3. Make sure the scripts are executable:

```bash
chmod +x "swift bar"/*.sh
```

## Private Configuration

Secrets are not stored in the scripts. The balance plugins load a private `.env` file from the `swift bar` plugin directory, then fall back to environment variables.

| Variable | Used by |
| --- | --- |
| `NF_VIDEO_COOKIE` | `swift bar/nf-video-balance.5m.sh` |
| `DEEPSEEK_TOKEN` | `swift bar/deepseek-balance.1h.sh` |

Create a private config file:

```bash
cp "swift bar/.env.example" "swift bar/.env"
```

Then edit `swift bar/.env`:

```bash
NF_VIDEO_COOKIE='your cookie'
DEEPSEEK_TOKEN='your token'
```

Restart SwiftBar after editing `.env`. The `.env` file is ignored by Git.

## Notes

- Error details are written to `/tmp/swiftbar-*.err` and linked from each plugin dropdown.
- Network speed keeps a small state file at `/tmp/swiftbar-network-speed.state`.
- Balance APIs may change or reject expired credentials. Refresh the relevant environment variable when that happens.

## License

MIT
