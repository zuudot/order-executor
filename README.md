# order-executor

Local remote-order executor for [Zuudot](https://zuudot.com) (逐点交易).

This process keeps **exchange API credentials on your machine** and opens an **outbound** WebSocket to the trading platform. It does not expose an inbound trading port.

This repository ships **documentation, example config, and the install script**. Official images are on Docker Hub. Source code is not published.

[中文说明](README.zh-CN.md)

## How it works

```
Exchange (OKX / Bybit / Binance)
        ▲  private WS + signed REST (keys stay local)
        │
 your host ── order-executor ── outbound WSS ──▶ Zuudot Gateway
```

- One process can run many exchange accounts.
- Each `[[accounts]]` entry gets its own exchange connection and reverse Gateway session.
- `executor_id` and `account_id` must be unique in the config file.
- An account that stays unready is rebuilt without restarting the others.
- Command responses and unacknowledged events are kept in memory for reconnect replay. Restarting the process clears that state.

Supported exchanges: **OKX**, **Bybit**, **Binance**.

## Install

The installer checks for Docker, installs it if missing, and pulls the official image.

```bash
curl -fsSL https://raw.githubusercontent.com/zuudot/order-executor/main/install.sh | bash
```

Then edit `conf/config.toml` and start:

```bash
docker compose up -d
docker compose logs -f
```

Image: [`zuudot/order-executor`](https://hub.docker.com/r/zuudot/order-executor) (`:latest`, or pin a version such as `:0.1.0`).

```bash
./install.sh 0.1.0
# or
ORDER_EXECUTOR_IMAGE=zuudot/order-executor:0.1.0 ./install.sh
```

## Configuration

1. In the Zuudot UI/API, create one `remote_executor` binding per exchange account.
2. Copy that account's `executor_id` and `account_id`, plus your platform `user_id` and `api_key`.
3. Copy `conf/config.example.toml` to `conf/config.toml` and fill in values.

### Platform

| Field | Required | Notes |
| --- | --- | --- |
| `gateway_url` | yes | `wss://zuudot.com/api/trading-engine/executor-gateway/ws` |
| `user_id` | yes | Platform user id |
| `api_key` | yes | Platform API key for that user |
| `client_cert_path` / `client_key_path` | if mTLS | PEM files mounted next to the config |
| `ca_cert_path` | optional | Custom CA for the Gateway TLS |
| `reconnect_initial_ms` | no | Default `1000` |
| `reconnect_max_ms` | no | Default `30000` |

### Accounts

Repeat `[[accounts]]` for each exchange account.

| Field | Required | Notes |
| --- | --- | --- |
| `executor_id` | yes | From the platform; unique in this file |
| `account_id` | yes | From the platform; unique in this file |
| `name` | yes | `okx`, `bybit`, or `binance` |
| `api_key` / `secret` | yes | Exchange credentials stored only on this host |
| `passphrase` | OKX | Leave empty for Bybit/Binance |
| `category` | no | `spot`, `linear` (default), or `inverse` |
| `account_mode` | no | e.g. `linear` |

### Runtime (optional)

```toml
[order]
maker_timeout_ms = 300

[runtime]
health_check_interval_ms = 30000
exchange_unready_restart_ms = 180000
```

The periodic `account runtime health` log reports both the exchange WebSocket state and the reverse Gateway connection for every account.

Full example: [`conf/config.example.toml`](conf/config.example.toml).

### Environment

| Variable | Meaning |
| --- | --- |
| `CONFIG_FILE` | Path to the TOML file (required unless `conf/${RUST_ENV}.toml` exists next to the binary) |
| `RUST_ENV` | Used only when `CONFIG_FILE` is unset; looks for `conf/<env>.toml` |
| `RUST_LOG` | Log filter, e.g. `info` or `order_executor=debug` |

## Security

- Restrict the exchange key to **read + trade**. Do **not** enable withdrawal.
- Apply an exchange IP allowlist to the machine that runs this process.
- Never commit `conf/config.toml`, certificates, or private keys.
- See [SECURITY.md](SECURITY.md).

## Platform TLS

Production Gateway connections use `wss://`. If the platform requires client certificates, set `client_cert_path` and `client_key_path` (and `ca_cert_path` when you need a custom CA).

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Process exits immediately | `CONFIG_FILE` path, TOML syntax, missing `[[accounts]]` |
| `unsupported exchange name` | `name` must be `okx`, `bybit`, or `binance` |
| Duplicate id error | `executor_id` / `account_id` must be unique in the file |
| Gateway keeps reconnecting | `user_id`, platform `api_key`, `gateway_url`, mTLS certs |
| Exchange stays unready | Exchange key/secret/passphrase, IP allowlist, `category` |
| Docker cannot read config | File must be readable by uid `10001` |

## Versioning

Docker Hub tags (`zuudot/order-executor:0.1.0`) are the source of truth. See [CHANGELOG.md](CHANGELOG.md).

## License

Official images and this documentation are proprietary. See [LICENSE](LICENSE). Source code is not included in this repository.
