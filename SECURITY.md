# Security

The order-executor holds **exchange API keys on the machine where it runs**. Treat that host and the config file as production secrets.

## Required key hygiene

- Create exchange keys with **trade / read** permissions only. Never enable withdrawal.
- Restrict each key with the exchange IP allowlist to the host that runs this process.
- Keep `conf/config.toml` and TLS private keys off git, chat, and screenshots.
- Rotate platform and exchange keys if they may have leaked.

## Reporting a vulnerability

Do not file a public GitHub issue for a security report.

Email the maintainers through the Zuudot platform support channel, and include:

- affected binary version (GitHub Release tag)
- impact (credential leak, unauthorized orders, auth bypass, etc.)
- reproduction notes that do **not** include live API keys

If a key may already be exposed, revoke it on the exchange and the platform first, then report.
