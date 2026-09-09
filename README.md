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

Create a working directory first (do not run this from `/`). The installer checks for Docker, installs it if missing, and pulls the official image.

```bash
mkdir -p ~/order-executor && cd ~/order-executor
curl -fsSL https://raw.githubusercontent.com/zuudot/order-executor/main/install.sh | bash
```

That directory now looks like:

```
~/order-executor/                 ← the directory you cd'd into; docker-compose.yml lives here
  docker-compose.yml
  conf/
    config.example.toml           ← example from the repo
    config.toml                   ← the file you edit (not /conf/config.toml)
```

`conf/config.toml` in this README and `./conf/config.toml` in Compose are relative to that working directory, **not** the filesystem root.

Then edit the config and start:

```bash
# still inside ~/order-executor
nano conf/config.toml
sudo chown 10001:10001 conf/config.toml && chmod 600 conf/config.toml   # Linux
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
3. Edit `conf/config.toml` in the working directory (the installer already copied it from the example). Do not put it at `/conf/config.toml`.

`docker-compose.yml` mounts that host file into the container: `./conf/config.toml` → `/app/conf/config.toml`. Only edit the host file.

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

Full example: [`conf/config.example.toml`](conf/config.example.toml) in the working directory.

### Environment

| Variable | Meaning |
| --- | --- |
| `CONFIG_FILE` | Path inside the container. Compose sets this to `/app/conf/config.toml`, which is the host working directory's `conf/config.toml` |
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
