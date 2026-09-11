# order-executor

[逐点交易](https://zuudot.com)（ZUUDOT）的本地远端下单执行器。

进程把**交易所 API 密钥留在你自己的机器上**，再主动向外连接平台 WebSocket。它**不会**对外开放交易端口。

本仓库只提供**文档、配置样例和安装脚本**。官方镜像发布在 Docker Hub。源码不公开。

[English](README.md)

## 工作方式

```
交易所 (OKX / Bybit / Binance)
        ▲  私有 WS + 签名 REST（密钥不出本机）
        │
 本机 ── order-executor ── 出站 WSS ──▶ 逐点 Gateway
```

- 一个进程可以跑多个交易所账户。
- 每个 `[[accounts]]` 独立建立交易所连接和反向 Gateway 会话。
- 配置文件里的 `executor_id`、`account_id` 必须唯一。
- 某个账户长时间未就绪时，只重建该账户，不影响其它账户。
- 指令回执和未确认事件会留在内存里，供断线重连回放。进程重启后这些状态会清空。

当前支持：**OKX**、**Bybit**、**Binance**。

## 安装

先建一个工作目录再跑安装脚本（不要在系统根目录 `/` 下执行）。脚本会检查 Docker，没有就自动安装，然后拉取官方镜像。

```bash
mkdir -p ~/order-executor && cd ~/order-executor
curl -fsSL https://raw.githubusercontent.com/zuudot/order-executor/main/install.sh | bash
```

完成后当前目录是：

```
~/order-executor/                 ← 你刚才 cd 进去的目录，也是 docker-compose.yml 所在处
  docker-compose.yml
  conf/
    config.example.toml           ← 仓库样例
    config.toml                   ← 要编辑的真实配置（不是 /conf/config.toml）
```

文档里的 `conf/config.toml`、compose 里的 `./conf/config.toml`，都是相对这个工作目录，**不是** Linux 根目录。

编辑配置后启动：

```bash
# 仍在 ~/order-executor 下
nano conf/config.toml
sudo chown 10001:10001 conf/config.toml && chmod 600 conf/config.toml   # Linux
docker compose up -d
docker compose logs -f
```

镜像：[`zuudot/order-executor`](https://hub.docker.com/r/zuudot/order-executor)（默认 `:latest`，也可钉死版本如 `:0.1.3`）。

```bash
./install.sh 0.1.3
# 或
ORDER_EXECUTOR_IMAGE=zuudot/order-executor:0.1.3 ./install.sh
```

## 配置

1. 在逐点控制台/API 为每个交易所账户创建一个 `remote_executor` 绑定。
2. 记下该账户的 `executor_id`、`account_id`，以及平台 `user_id` 和 `api_key`。
3. 编辑工作目录里的 `conf/config.toml`（安装脚本已从样例复制好）。不要写到 `/conf/config.toml`。

`docker-compose.yml` 会把宿主机上的这份文件挂进容器：`./conf/config.toml` → 容器内 `/app/conf/config.toml`。你只改宿主机上那一份。

### 平台

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `gateway_url` | 是 | `wss://zuudot.com/api/trading-engine/executor-gateway/ws` |
| `user_id` | 是 | 平台用户 ID |
| `api_key` | 是 | 该用户的平台 API Key |
| `client_cert_path` / `client_key_path` | mTLS 时 | PEM 证书，和配置放在一起挂载 |
| `ca_cert_path` | 可选 | Gateway TLS 的自定义 CA |
| `reconnect_initial_ms` | 否 | 默认 `1000` |
| `reconnect_max_ms` | 否 | 默认 `30000` |

### 账户

每个交易所账户一段 `[[accounts]]`。

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `executor_id` | 是 | 平台签发，文件内唯一 |
| `account_id` | 是 | 平台签发，文件内唯一 |
| `name` | 是 | `okx`、`bybit` 或 `binance` |
| `api_key` / `secret` | 是 | 交易所密钥，只存在本机 |
| `passphrase` | OKX 需要 | Bybit / Binance 留空 |
| `category` | 否 | `spot`、`linear`（默认）或 `inverse` |
| `account_mode` | 否 | 例如 `linear` |

### 运行参数（可选）

```toml
[order]
maker_timeout_ms = 300

[runtime]
health_check_interval_ms = 30000
exchange_unready_restart_ms = 180000
```

周期性 `account runtime health` 日志会同时打出交易所 WS 和反向 Gateway 的状态。

完整样例见工作目录中的 [`conf/config.example.toml`](conf/config.example.toml)。

### 环境变量

| 变量 | 含义 |
| --- | --- |
| `CONFIG_FILE` | 容器内 TOML 路径。compose 已设为 `/app/conf/config.toml`，对应宿主机工作目录下的 `conf/config.toml` |
| `RUST_ENV` | 仅在未设置 `CONFIG_FILE` 时使用 |
| `RUST_LOG` | 日志级别，例如 `info` |

## 安全

- 交易所密钥只开**读取 + 交易**，**不要**开提币。
- 在交易所侧为这台机器配置 IP 白名单。
- 不要把 `conf/config.toml`、证书和私钥提交到 git。
- 详见 [SECURITY.md](SECURITY.md)。

## 排障

| 现象 | 检查 |
| --- | --- |
| 进程立刻退出 | `CONFIG_FILE` 路径、TOML 语法、是否缺少 `[[accounts]]` |
| `unsupported exchange name` | `name` 只能是 `okx` / `bybit` / `binance` |
| duplicate id | 同一文件里 `executor_id` / `account_id` 不能重复 |
| Gateway 不停重连 | `user_id`、平台 `api_key`、`gateway_url`、mTLS 证书 |
| 交易所一直 unready | 交易所密钥、IP 白名单、`category` |
| Docker 读不了配置 | 文件需要能被 uid `10001` 读取 |

## 版本

以 Docker Hub 的 tag（`zuudot/order-executor:0.1.3`）为准，见 [CHANGELOG.md](CHANGELOG.md)。

## 许可

官方镜像和本文档为专有许可，见 [LICENSE](LICENSE)。本仓库不包含源码。
