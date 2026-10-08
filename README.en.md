<div align="center">

<a href="https://getroutekeeper.app/en/"><img src="icon.png" width="128" height="128" alt="Routekeeper"></a>

# Routekeeper

**Every app gets its own route.**

A per-app proxy router and firewall for macOS that keeps traffic from slipping past the proxy.

[Русский](README.md) · **English**

[![Latest release](https://img.shields.io/github/v/release/ilyabazhenov/routekeeper?style=flat-square&label=release&color=ffb547&labelColor=0a0f1f)](../../releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-ffb547?style=flat-square&logo=apple&logoColor=white&labelColor=0a0f1f)](https://getroutekeeper.app/en/docs/start/)
[![Notarized by Apple](https://img.shields.io/badge/Developer_ID-notarized-3ecf8e?style=flat-square&labelColor=0a0f1f)](https://getroutekeeper.app/en/docs/start/)
[![No telemetry](https://img.shields.io/badge/no_telemetry-3ecf8e?style=flat-square&labelColor=0a0f1f)](https://getroutekeeper.app/en/privacy/)

<br>

<a href="../../releases/latest/download/Routekeeper.dmg"><img src="https://img.shields.io/badge/Download_for_Mac-Routekeeper.dmg-ffb547?style=for-the-badge&logo=apple&logoColor=white&labelColor=0a0f1f" alt="Download for Mac" height="40"></a>

**[Website](https://getroutekeeper.app/en/)** ·
**[Docs](https://getroutekeeper.app/en/docs/)** ·
**[Quick start](https://getroutekeeper.app/en/docs/start/)** ·
**[Your own server](https://getroutekeeper.app/en/docs/server/)** ·
**[What's new](https://getroutekeeper.app/en/docs/changelog/)**

<br>

<a href="https://getroutekeeper.app/en/"><img src=".github/readme/app-en.png" alt="Routekeeper window: Telegram and Slack go through the proxy, Safari and Zoom go direct, Adobe Updater is blocked" width="100%"></a>

</div>

<br>

Routekeeper sends the apps you choose through your proxy server, leaves the rest alone, and makes sure nothing slips past the proxy. For every outgoing connection it decides what to do:

| | Action | For example |
|:-:|---|---|
| 🟢 | **Through proxy** — via the SOCKS5, HTTP or HTTPS proxy you picked | Telegram, Slack, `git` and `curl` in the terminal |
| ⚪ | **Direct** — as if Routekeeper weren't there | Your bank, local services |
| 🔴 | **Dead end** — the connection is dropped | An unknown program trying to phone home |
| 🟡 | **Ask** — a prompt with the signature, path and parent processes | Anything without a rule yet |

## Features

**Routes**
- **One click per app:** through a proxy, direct, dead end or ask. Apps are recognized by their developer signature together with their helper processes, so a rule for your terminal also covers `git`, `npm` and `curl`.
- **Services:** ready-made address sets — video, messengers, AI services, developer tools — so you can send just those through the proxy instead of the whole app. The catalog updates from the website, no new app version needed.
- **Exception rules** by domain, `*.` pattern, IP, subnet, port and protocol. The most specific rule wins, not the first one in the list.

**Doesn't leak**
- **If the proxy is down,** connections are refused instead of going direct (unless you allow it). Routes can be switched to another proxy — and switched back.
- **UDP and QUIC** are closed for proxied apps, and the proxy resolves host names.
- **Leaks:** DNS to your ISP, UDP and processes that went past the proxy, each with a hint on how to close it.

**See what's going on**
- **Overview:** whether everything works, the most serious problem and the button that fixes it; each proxy's health and what's going through it right now.
- **Monitor** of every connection and its route, with a traffic map.
- **Four firewall modes:** Proxy Only, Silent, Ask, Block All. After install Routekeeper only routes and asks nothing.

**Your own proxy server**
- **Your Own Server… wizard:** enter the IP, server password and domain, and Routekeeper sets up an HTTPS proxy on your VPS and adds it. Later you can check, update or change its password from the proxy's card.
- **Or by hand,** with one command on a Debian or Ubuntu server — the [`server.sh`](server.sh) script from this repository:

  ```bash
  curl -fsSL https://getroutekeeper.app/server.sh | bash -s -- --domain my-name.duckdns.org
  ```

Proxies: SOCKS5, HTTP CONNECT and HTTPS, with or without a login and password; you can just paste a `socks5://user:pass@host:port` string. VLESS and Shadowsocks work through their client's local SOCKS5 port. The interface is in English and Russian.

What Routekeeper can't do and why is in [Limits](https://getroutekeeper.app/en/docs/limits/). The main one: only TCP goes through the proxy, so it won't help calls or games.

## Install

1. **[Download Routekeeper.dmg](../../releases/latest/download/Routekeeper.dmg)** and drag Routekeeper into Applications.
2. **Open it and allow the network extension.** macOS asks for three permissions; you need an admin account.
3. **Add a proxy** — your own, or [set up a server from the app](https://getroutekeeper.app/en/docs/server/).
4. **Enter a license.** Without one you can set everything up, but Routekeeper doesn't route traffic. How to get one: [License](https://getroutekeeper.app/en/docs/license/).

Step by step: [Quick start](https://getroutekeeper.app/en/docs/start/).

> [!NOTE]
> **Requirements:** macOS 14 Sonoma or later, Apple Silicon or Intel.
> The DMG is signed with Developer ID and notarized by Apple. Routekeeper checks for updates itself and installs them after you confirm. To hear about new versions here, click **Watch → Custom → Releases** at the top of this page.

## Privacy

Routekeeper collects no telemetry, needs no account and sends nothing to the developer. It only goes online for updates, the service catalog and, through your proxy, to check the external IP. Rules and passwords are kept by the system extension in a root-only file. Details: [privacy policy](https://getroutekeeper.app/en/privacy/).

## Report a bug

1. Check [Troubleshooting](https://getroutekeeper.app/en/docs/troubleshooting/) for common problems and app messages.
2. Collect diagnostics: **Help → Collect Diagnostics…** The archive lands on your desktop. It has your settings without passwords, but with the proxy address and login, recent connections and 30 minutes of logs. **Review it before sending:** issues here are public.
3. [Open an issue](../../issues/new/choose): Routekeeper and macOS versions, what you did, what you expected, what happened.

<details>
<summary>The app won't open — how to collect logs</summary>

```bash
log show --last 30m --info --predicate 'subsystem BEGINSWITH "app.getroutekeeper" OR subsystem BEGINSWITH "dev.ilyabazenov"' > routekeeper.log
```

</details>

## What's in this repository

The app's source code is closed. Here you'll find:

| | |
|---|---|
| [Releases](../../releases) | Routekeeper.dmg, every version |
| [CHANGELOG.md](CHANGELOG.md) | What's new, version by version (in Russian; [English](https://getroutekeeper.app/en/docs/changelog/)) |
| [`server.sh`](server.sh) | Installer for your own HTTPS proxy on Debian or Ubuntu |
| [Issues](../../issues) | Bugs and suggestions |
| Everything else | The [getroutekeeper.app](https://getroutekeeper.app/en/) website and docs (GitHub Pages) |

<br>

<div align="center">
<sub><a href="https://getroutekeeper.app/en/">getroutekeeper.app</a></sub>
</div>
