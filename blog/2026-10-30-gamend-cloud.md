# Gamend Cloud: Hosted Dev Gamend Servers

Gamend, the open source Elixir multiplayer game server now has hosting. This is to help devs get started quickly, and to test all our system, including payment. We offer 1 month of free trial.

## Why

Two reasons:

- **To test everything for real.** gamend.org is itself a Gamend app. Selling servers on it runs the parts of Gamend that are hardest to test on a laptop with real money and real users: Stripe subscriptions, upgrades and downgrades, accounts, groups, notifications, emails, settings and background jobs.
- **To get people started easily.** No machine to rent, no Docker, no TLS or DNS. A name and a button.

Gamend stays open source (MIT), and self-hosting is still supported and documented.

## Features

- **Code**: the [starter](https://github.com/appsinacup/gamend_starter), your own GitHub repository (deployed on every push), or any git URL.
- **Builds and logs**
- **Settings**
- **Your own domain**: a CNAME and a TXT record.
- **Groups**: share a server with your team (reuses the gamend group feature)
- **Export**: export the whole data and self host.

## Sizes

| Size | Memory | CPU | Players | Traffic | SQLite | Postgres |
|-|-|-|-|-|-|-|
| **Small** | 1 GB | 0.5 | 1,000 | 250 GB | $5 | $10 |
| **Standard** | 2 GB | 1 | 2,000 | 1 TB | $10 | $20 |
| **Large** | 4 GB | 2 | 4,000 | 2 TB | $20 | $40 |

Prices are per month, VAT included. Player caps come from the [load tests](https://gamend.org/docs/performance). Postgres runs as its own container beside the server.

**Your first server is free for 30 days**, on Small or Standard with SQLite.

## Early access

Servers run on our own machines in Europe. There is no uptime promise yet.

- [Servers](https://gamend.org/servers)
- [Self-hosting guide](https://gamend.org/docs/deployment)
- [Github](https://github.com/appsinacup/gamend)

## Examples

- [Demo](https://demo.gamend.cloud)
- [Polyglot Pirates](https://polyglotpirates.com)
- [Forge](https://balaurengine.org)
