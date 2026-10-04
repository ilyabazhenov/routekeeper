#!/bin/bash
# Routekeeper: your own HTTPS proxy (HTTP CONNECT over TLS) on a Debian/Ubuntu server.
# Caddy with klzgrad's forwardproxy@naive build, Let's Encrypt certificate, probe resistance,
# decoy site, systemd service, BBR, fail2ban for SSH, automatic security updates.
# Safe to re-run: keeps the login and password, restarts Caddy only when something changed.
#
# Usage, as root on the server:
#   curl -fsSL https://getroutekeeper.app/server.sh | bash -s -- --domain my-name.duckdns.org
#
# Options:
#   --domain NAME      domain whose A record points at this server (required)
#   --new-password     replace the login and password
#   --no-bbr           leave TCP congestion control as is
#   --no-fail2ban      don't set up fail2ban for SSH
#   --no-auto-updates  don't turn on automatic security updates
#   --json             print the result as JSON (for scripts and apps)
#   --lang ru|en       language of the messages (default: from LANG)
#   --uninstall        remove the proxy; BBR, fail2ban and updates stay
#
# Guide: https://getroutekeeper.app/docs/server/
# Source: site/server.sh in the Routekeeper repo, published as is.
set -euo pipefail

CADDY_VERSION="v2.11.2-naive"
CADDY_SHA256="19eccb7321dd877a5fb4a3dba6ef1b745185188b616c96cc6201f1a1fc0380a8"
CREDS=/etc/caddy/proxy-credentials

DOMAIN=""
NEW_PASSWORD=0
BBR=1
FAIL2BAN=1
AUTO_UPDATES=1
JSON=0
UNINSTALL=0
RU=0
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*) RU=1 ;; esac
# ssh passes the Mac's LANG, which the server often lacks, and perl tools (apt, update-rc.d) complain.
export LC_ALL=C.UTF-8

# Messages go to stderr; stdout carries only the result, so --json output stays parseable.
pick() { if [ "$RU" = 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
say() { printf '%s\n' "$(pick "$1" "$2")" >&2; }
step() { printf '\n==> %s\n' "$(pick "$1" "$2")" >&2; }
die() { printf '\n✗ %s\n' "$(pick "$1" "$2")" >&2; exit 1; }

usage() {
  echo "Usage: server.sh --domain NAME [--new-password] [--no-bbr] [--no-fail2ban] [--no-auto-updates] [--json] [--lang ru|en] [--uninstall]" >&2
  exit 2
}

APT_UPDATED=0
apt_install() {
  # Fresh servers often run apt on first boot, so wait for the lock instead of failing.
  # apt's chatter (debconf notes and the like) is shown only when it fails.
  local log
  log=$(mktemp)
  if [ "$APT_UPDATED" = 0 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update -qq </dev/null >"$log" 2>&1 \
      || { cat "$log" >&2; rm -f "$log"; die "apt-get update не сработал." "apt-get update failed."; }
    APT_UPDATED=1
  fi
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y -qq "$@" </dev/null >"$log" 2>&1 \
    || { cat "$log" >&2; rm -f "$log"; die "Не удалось установить: $*" "Couldn't install: $*"; }
  rm -f "$log"
}

# Installs $1 as $2 with mode $3 and group $4 if the content differs. Returns 0 when it changed.
put() {
  local src=$1 dst=$2 mode=$3 group=${4:-root}
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then rm -f "$src"; return 1; fi
  install -m "$mode" -o root -g "$group" "$src" "$dst"
  rm -f "$src"
}

is_ipv4() { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

preflight() {
  [ "$(id -u)" = 0 ] || die "Запустите от root: … | sudo bash -s -- --domain $DOMAIN" \
                            "Run as root: … | sudo bash -s -- --domain $DOMAIN"
  [ -r /etc/os-release ] && . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*) ;;
    *) die "Нужен Debian или Ubuntu, а здесь ${PRETTY_NAME:-неизвестная ОС}." \
           "Debian or Ubuntu is required, this is ${PRETTY_NAME:-an unknown OS}." ;;
  esac
  [ -d /run/systemd/system ] || die "Нужен systemd." "systemd is required."
  [ "$(uname -m)" = x86_64 ] || die "Нужен сервер x86_64 (amd64): для $(uname -m) готовой сборки Caddy с прокси нет." \
                                    "An x86_64 (amd64) server is required: there is no ready Caddy proxy build for $(uname -m)."
  say "ОС: ${PRETTY_NAME:-?} ($(uname -m))" "OS: ${PRETTY_NAME:-?} ($(uname -m))"

  local missing=()
  command -v curl >/dev/null || missing+=(curl)
  command -v xz >/dev/null || missing+=(xz-utils)
  command -v openssl >/dev/null || missing+=(openssl)
  command -v ss >/dev/null || missing+=(iproute2)
  [ -f /etc/ssl/certs/ca-certificates.crt ] || missing+=(ca-certificates)
  [ ${#missing[@]} = 0 ] || apt_install "${missing[@]}"
}

check_dns() {
  step "Проверка домена $DOMAIN" "Checking the domain $DOMAIN"
  SERVER_IP=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true)
  is_ipv4 "$SERVER_IP" || die "Не удалось узнать внешний IPv4 сервера. Нужен сервер с публичным IPv4." \
                              "Couldn't find the server's public IPv4. A server with a public IPv4 is required."
  local resolved
  resolved=$(getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u | tr '\n' ' ' || true)
  say "сервер: $SERVER_IP, $DOMAIN → ${resolved:-нет записи}" "server: $SERVER_IP, $DOMAIN → ${resolved:-no record}"
  case " $resolved " in
    *" $SERVER_IP "*) ;;
    *) die "A-запись $DOMAIN должна указывать на $SERVER_IP. Исправьте её у регистратора или в DuckDNS и подождите пару минут." \
           "The A record of $DOMAIN must point at $SERVER_IP. Fix it at your registrar or in DuckDNS and wait a couple of minutes." ;;
  esac
}

check_ports() {
  # Ports 80 (Let's Encrypt HTTP-01) and 443 must be free or already ours.
  local busy
  busy=$(ss -tlnpH '( sport = :80 or sport = :443 )' | grep -v '"caddy"' | grep -o 'users:(("[^"]*"' | cut -d'"' -f2 | sort -u | paste -sd, - | sed 's/,/, /g' || true)
  [ -z "$busy" ] || die "Порты 80 и 443 заняты: ${busy}. Похоже, здесь уже работает веб-сервер или VPN-панель (nginx, Xray, 3x-ui, Marzban). Освободите порты или возьмите отдельный сервер." \
                        "Ports 80 and 443 are taken by: ${busy}. Looks like a web server or a VPN panel (nginx, Xray, 3x-ui, Marzban) already runs here. Free the ports or use a separate server."
  # A Caddy we didn't set up serves someone's sites: don't overwrite its config.
  if [ -f /etc/caddy/Caddyfile ] && ! grep -q forward_proxy /etc/caddy/Caddyfile; then
    die "На сервере уже есть Caddy со своими сайтами (/etc/caddy/Caddyfile). Скрипт его не трогает: возьмите отдельный сервер." \
        "This server already runs Caddy with its own sites (/etc/caddy/Caddyfile). The script won't touch it: use a separate server."
  fi
}

open_firewall() {
  command -v ufw >/dev/null && ufw status 2>/dev/null | grep "Status: active" >/dev/null || return 0
  ufw allow 80/tcp >/dev/null && ufw allow 443/tcp >/dev/null && ufw allow 443/udp >/dev/null
  say "ufw: открыты порты 80 и 443" "ufw: opened ports 80 and 443"
}

install_caddy() {
  step "Caddy $CADDY_VERSION" "Caddy $CADDY_VERSION"
  CADDY_CHANGED=0
  # No grep -q after a pipe: with pipefail an early exit turns into SIGPIPE for the writer.
  if ! /usr/local/bin/caddy version 2>/dev/null | grep "^${CADDY_VERSION%-naive} " >/dev/null; then
    local tmp
    tmp=$(mktemp -d)
    curl -fsSL --retry 3 -o "$tmp/c.tar.xz" "https://github.com/klzgrad/forwardproxy/releases/download/$CADDY_VERSION/caddy-forwardproxy-naive.tar.xz"
    echo "$CADDY_SHA256  $tmp/c.tar.xz" | sha256sum -c --status \
      || { rm -rf "$tmp"; die "Контрольная сумма Caddy не совпала, установка остановлена." "Caddy checksum mismatch, stopping."; }
    tar -xJf "$tmp/c.tar.xz" -C "$tmp"
    install -m 0755 "$tmp/caddy-forwardproxy-naive/caddy" /usr/local/bin/caddy
    rm -rf "$tmp"
    CADDY_CHANGED=1
  fi
  /usr/local/bin/caddy list-modules | grep '^http.handlers.forward_proxy$' >/dev/null \
    || die "В сборке Caddy нет forward_proxy." "The Caddy build lacks forward_proxy."

  id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy
  install -d -m 0755 /etc/caddy /var/www/site

  if [ "$NEW_PASSWORD" = 1 ] || [ ! -f "$CREDS" ]; then
    local u p
    u="u$(openssl rand -hex 6)"
    p="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40)"
    ( umask 077; printf 'PROXY_USER=%s\nPROXY_PASS=%s\n' "$u" "$p" > "$CREDS" )
  fi
  . "$CREDS"

  # Decoy page: what anyone without the password sees.
  if [ ! -f /var/www/site/index.html ]; then
    cat > /var/www/site/index.html <<'HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Notes</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:640px;margin:10vh auto;padding:0 16px;color:#222}</style></head>
<body><h1>Notes</h1><p>Personal page. Nothing to see here yet.</p></body></html>
HTML
  fi
  chmod 0644 /var/www/site/index.html

  local tmp_conf
  tmp_conf=$(mktemp)
  cat > "$tmp_conf" <<EOF
{
	order forward_proxy before file_server
}

:443, $DOMAIN {
	tls {
		protocols tls1.2 tls1.3
	}
	forward_proxy {
		basic_auth $PROXY_USER $PROXY_PASS
		hide_ip
		hide_via
		probe_resistance
	}
	file_server {
		root /var/www/site
	}
}
EOF
  /usr/local/bin/caddy validate --adapter caddyfile --config "$tmp_conf" >/dev/null 2>&1 \
    || { rm -f "$tmp_conf"; die "Caddy не принял конфигурацию." "Caddy rejected the configuration."; }
  put "$tmp_conf" /etc/caddy/Caddyfile 0640 caddy && CADDY_CHANGED=1

  local tmp_unit
  tmp_unit=$(mktemp)
  cat > "$tmp_unit" <<'EOF'
[Unit]
Description=Caddy (forwardproxy naive)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  if put "$tmp_unit" /etc/systemd/system/caddy.service 0644; then
    systemctl daemon-reload
    CADDY_CHANGED=1
  fi
  systemctl enable -q caddy
  if [ "$CADDY_CHANGED" = 1 ] || ! systemctl is-active -q caddy; then
    systemctl restart caddy
    say "Caddy перезапущен" "Caddy restarted"
  else
    say "Caddy уже настроен, перезапуск не нужен" "Caddy is already set up, no restart needed"
  fi
}

setup_bbr() {
  [ "$BBR" = 1 ] || return 0
  step "BBR" "BBR"
  # On a ~200 ms route BBR raised single-stream speed from ~0.5 to ~3 MB/s.
  # 99-zz makes the file apply last, after any hosting provider's tuning.
  modprobe tcp_bbr 2>/dev/null || true
  local tmp
  tmp=$(mktemp); echo tcp_bbr > "$tmp"; put "$tmp" /etc/modules-load.d/bbr.conf 0644 || true
  tmp=$(mktemp); printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > "$tmp"
  put "$tmp" /etc/sysctl.d/99-zz-bbr.conf 0644 || true
  sysctl -q -p /etc/sysctl.d/99-zz-bbr.conf
  local dev
  dev=$(ip route show default | awk '{print $5; exit}')
  if [ -n "$dev" ] && ! tc qdisc show dev "$dev" | grep '^qdisc fq ' >/dev/null; then
    tc qdisc replace dev "$dev" root fq
  fi
  say "TCP: $(sysctl -n net.ipv4.tcp_congestion_control)" "TCP: $(sysctl -n net.ipv4.tcp_congestion_control)"
}

setup_fail2ban() {
  [ "$FAIL2BAN" = 1 ] || return 0
  step "fail2ban для SSH" "fail2ban for SSH"
  local pkgs=()
  command -v fail2ban-client >/dev/null || pkgs+=(fail2ban)
  python3 -c 'import systemd.journal' 2>/dev/null || pkgs+=(python3-systemd)
  command -v nft >/dev/null || pkgs+=(nftables)
  [ ${#pkgs[@]} = 0 ] || apt_install "${pkgs[@]}"

  # Never ban the server itself or the address this script runs from.
  local client_ip=${SSH_CLIENT:-}
  client_ip=${client_ip%% *}
  is_ipv4 "$client_ip" || client_ip=""
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<EOF
# Routekeeper: SSH brute-force protection. Written by server.sh, re-running it overwrites this file.
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 $SERVER_IP${client_ip:+ $client_ip}
findtime = 1h
maxretry = 5
bantime = 1d
# Repeat offenders: 1d, 2d, 4d, ... up to 4 weeks.
bantime.increment = true
bantime.maxtime = 4w
banaction = nftables-multiport
banaction_allports = nftables-allports

[sshd]
enabled = true
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _SYSTEMD_UNIT=sshd.service + _COMM=sshd + _COMM=sshd-session
EOF
  local changed=0
  put "$tmp" /etc/fail2ban/jail.d/zz-routekeeper.local 0644 && changed=1
  # Keep ban history long enough for bantime.increment to recognise repeat offenders.
  tmp=$(mktemp)
  printf '[Definition]\ndbpurgeage = 30d\n' > "$tmp"
  put "$tmp" /etc/fail2ban/fail2ban.d/zz-routekeeper.local 0644 && changed=1
  fail2ban-client -t >/dev/null 2>&1 || die "fail2ban не принял конфигурацию." "fail2ban rejected the configuration."
  systemctl enable -q fail2ban
  if [ "$changed" = 1 ] || ! systemctl is-active -q fail2ban; then systemctl restart fail2ban; fi
  local i
  for i in $(seq 1 10); do fail2ban-client status sshd >/dev/null 2>&1 && break; sleep 1; done
  fail2ban-client status sshd >/dev/null 2>&1 || die "fail2ban не запустил защиту SSH." "fail2ban didn't start the SSH jail."
  say "5 неудачных входов за час → бан на сутки, повторно дольше" "5 failed logins in an hour → banned for a day, longer for repeat offenders"
}

setup_auto_updates() {
  [ "$AUTO_UPDATES" = 1 ] || return 0
  step "Автоматические обновления безопасности" "Automatic security updates"
  dpkg -s unattended-upgrades >/dev/null 2>&1 || apt_install unattended-upgrades
  local tmp
  tmp=$(mktemp)
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > "$tmp"
  put "$tmp" /etc/apt/apt.conf.d/20auto-upgrades 0644 || true
  say "включены, сервер сам не перезагружается" "on, the server never reboots by itself"
}

verify() {
  step "Проверки" "Checks"
  # Talk to Caddy on this machine, so the checks don't depend on hairpin routing.
  local resolve=(--resolve "$DOMAIN:443:127.0.0.1")
  local ok=0 i
  for i in $(seq 1 45); do
    curl -fsS -o /dev/null --max-time 5 "${resolve[@]}" "https://$DOMAIN/" 2>/dev/null && { ok=1; break; }
    sleep 2
  done
  if [ "$ok" = 0 ]; then
    local reason
    reason=$(journalctl -u caddy -n 50 -o cat --no-pager 2>/dev/null | grep '"level":"error"' | tail -1 \
      | grep -oE '"error":"([^"\\]|\\.)*"' | head -1 | cut -c10-400 || true)
    [ -z "$reason" ] || say "Let's Encrypt: $reason" "Let's Encrypt: $reason"
    die "Caddy не получил сертификат Let's Encrypt. Чаще всего порты 80 и 443 закрыты в панели хостера (firewall, security group): откройте их и запустите скрипт ещё раз." \
        "Caddy couldn't get a Let's Encrypt certificate. Usually ports 80 and 443 are closed in the hosting panel (firewall, security group): open them and run the script again."
  fi
  say "  ✓ сертификат Let's Encrypt, сайт-заглушка открывается" "  ✓ Let's Encrypt certificate, decoy site is up"

  local exit_ip
  exit_ip=$(curl -fsS --max-time 20 "${resolve[@]}" -x "https://$DOMAIN:443" -K - https://api.ipify.org <<<"proxy-user = \"$PROXY_USER:$PROXY_PASS\"" 2>/dev/null || true)
  [ "$exit_ip" = "$SERVER_IP" ] || die "Прокси с паролем не работает (ответ: '${exit_ip}')." "The proxy doesn't work with the password (got '${exit_ip}')."
  say "  ✓ прокси с паролем работает, внешний IP $SERVER_IP" "  ✓ proxy works with the password, exit IP $SERVER_IP"

  local probe
  # %{http_connect} is the proxy's answer to CONNECT; %{http_code} stays 000 when the tunnel fails.
  probe=$(curl -s --max-time 10 -o /dev/null -w '%{http_connect}' "${resolve[@]}" -p -x "https://$DOMAIN:443" https://api.ipify.org 2>/dev/null || true)
  [ "$probe" != 407 ] || die "Без пароля прокси выдаёт себя ответом 407." "Without the password the proxy gives itself away with 407."
  say "  ✓ без пароля сервер выглядит как обычный сайт" "  ✓ without the password the server looks like a plain website"
}

report() {
  local url="https://$PROXY_USER:$PROXY_PASS@$DOMAIN:443"
  if [ "$JSON" = 1 ]; then
    printf '{"type":"https","host":"%s","port":443,"username":"%s","password":"%s","url":"%s","serverIP":"%s","caddy":"%s"}\n' \
      "$DOMAIN" "$PROXY_USER" "$PROXY_PASS" "$url" "$SERVER_IP" "${CADDY_VERSION%-naive}"
    return
  fi
  if [ "$RU" = 1 ]; then
    cat <<EOF

Готово. Скопируйте строку и вставьте её в Routekeeper: «Прокси» → ⌘V (или кнопка «Вставить») → «Добавить».

  $url

Или заполните вручную: тип HTTPS, сервер $DOMAIN, порт 443, логин $PROXY_USER, пароль $PROXY_PASS.
Строка — это ключ от прокси: не публикуйте её. Посмотреть снова: cat $CREDS
EOF
  else
    cat <<EOF

Done. Copy the line and paste it into Routekeeper: Proxy → ⌘V (or the Paste button) → Add.

  $url

Or fill it in by hand: type HTTPS, server $DOMAIN, port 443, login $PROXY_USER, password $PROXY_PASS.
The line is the key to your proxy: keep it private. To see it again: cat $CREDS
EOF
  fi
}

uninstall() {
  [ "$(id -u)" = 0 ] || die "Запустите от root." "Run as root."
  if [ -f /etc/caddy/Caddyfile ] && ! grep -q forward_proxy /etc/caddy/Caddyfile; then
    die "Caddy на этом сервере ставил не Routekeeper, удалять его скрипт не будет." "Caddy on this server wasn't set up by Routekeeper, the script won't remove it."
  fi
  step "Удаление прокси" "Removing the proxy"
  systemctl disable --now -q caddy 2>/dev/null || true
  rm -f /etc/systemd/system/caddy.service
  systemctl daemon-reload
  rm -rf /etc/caddy /var/www/site /var/lib/caddy /usr/local/bin/caddy
  userdel caddy 2>/dev/null || true
  say "Прокси удалён. BBR, fail2ban и автообновления остались: они полезны и без прокси." \
      "The proxy is removed. BBR, fail2ban and automatic updates stay: they're useful without the proxy too."
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; shift 2 || usage ;;
      --new-password) NEW_PASSWORD=1; shift ;;
      --no-bbr) BBR=0; shift ;;
      --no-fail2ban) FAIL2BAN=0; shift ;;
      --no-auto-updates) AUTO_UPDATES=0; shift ;;
      --json) JSON=1; shift ;;
      --lang) case "${2:-}" in ru) RU=1 ;; en) RU=0 ;; *) usage ;; esac; shift 2 ;;
      --uninstall) UNINSTALL=1; shift ;;
      -h|--help) usage ;;
      *) usage ;;
    esac
  done
  if [ "$UNINSTALL" = 1 ]; then uninstall; return; fi
  DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  [[ $DOMAIN =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] \
    || die "Укажите домен: --domain my-name.duckdns.org" "Pass the domain: --domain my-name.duckdns.org"

  preflight
  check_dns
  check_ports
  open_firewall
  install_caddy
  setup_bbr
  setup_fail2ban
  setup_auto_updates
  verify
  report
}

# Everything runs from here, so a partially downloaded script does nothing.
main "$@"
