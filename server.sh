#!/bin/bash
# Routekeeper: your own HTTPS proxy (HTTP CONNECT over TLS) on a Debian/Ubuntu server.
# Caddy with klzgrad's forwardproxy@naive build, Let's Encrypt certificate, proxy closed to anyone
# without the password, placeholder site, systemd service, BBR, fail2ban for SSH, security updates.
# Safe to re-run: keeps the login and password, restarts Caddy only when something changed.
#
# Usage, as root on the server:
#   curl -fsSL https://getroutekeeper.app/server.sh | bash -s -- --domain my-name.duckdns.org
#
# Options:
#   --domain NAME      domain whose A record points at this server (required to install)
#   --new-password     replace the login and password
#   --no-bbr           leave TCP congestion control as is
#   --no-fail2ban      don't set up fail2ban for SSH
#   --no-auto-updates  don't turn on automatic security updates
#   --json             print the result as JSON (for scripts and apps)
#   --events           report progress as JSON lines on stderr instead of text (for apps)
#   --check            only check whether this server fits, change nothing (JSON on stdout)
#   --status           describe the installed proxy (JSON on stdout)
#   --lang ru|en       language of the messages (default: from LANG)
#   --uninstall        remove the proxy; BBR, fail2ban and updates stay
#
# Guide: https://getroutekeeper.app/docs/server/
# Source: site/server.sh in the Routekeeper repo, published as is. The Routekeeper app runs the same
# script over SSH with --json --events; the event ids and error codes are its contract (see
# docs/server-wizard.md) and change only together with the app.
set -Eeuo pipefail

# Bumped whenever the script changes what it sets up; written on the server, reported by --status.
SCRIPT_VERSION=2
CADDY_VERSION="v2.11.2-naive"
CADDY_SHA256="19eccb7321dd877a5fb4a3dba6ef1b745185188b616c96cc6201f1a1fc0380a8"
CREDS=/etc/caddy/proxy-credentials
MARKER=/etc/caddy/routekeeper-script

DOMAIN=""
NEW_PASSWORD=0
BBR=1
FAIL2BAN=1
AUTO_UPDATES=1
JSON=0
EVENTS=0
CHECK=0
STATUS=0
UNINSTALL=0
RU=0
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*) RU=1 ;; esac
# ssh passes the Mac's LANG, which the server often lacks, and perl tools (apt, update-rc.d) complain.
export LC_ALL=C.UTF-8

# --- Messages -------------------------------------------------------------------------------------
# Messages go to fd 3, which is the original stderr; stdout carries only the result, so --json, --check
# and --status stay parseable. Text mode prints lines for people; --events prints one JSON object per
# line for the app, and then other programs' stderr goes to a log instead (see main), so the event
# stream stays clean.
exec 3>&2
ERRLOG=""

pick() { if [ "$RU" = 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# A JSON string literal. Drops control characters other than tab and newline.
json_str() {
  local s
  s=$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037')
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}
# JSON event: event_line KIND KEY ID TEXT [EXTRA_JSON_FIELDS]
event_line() {
  printf '{"event":"%s","%s":"%s","text":%s%s}\n' "$1" "$2" "$3" "$(json_str "$4")" "${5:+,$5}" >&3
}

# Lines printed before an error or warning in text mode, and sent as "detail" in events.
DETAIL=""
detail_field() { [ -z "$DETAIL" ] || printf '"detail":%s' "$(json_str "$DETAIL")"; }

say() {
  if [ "$EVENTS" = 1 ]; then printf '{"event":"info","text":%s}\n' "$(json_str "$(pick "$1" "$2")")" >&3
  else printf '%s\n' "$(pick "$1" "$2")" >&3; fi
}
# step ID RU EN — a stage of the install; the app shows them as a checklist.
step() {
  if [ "$EVENTS" = 1 ]; then event_line step id "$1" "$(pick "$2" "$3")"
  else printf '\n==> %s\n' "$(pick "$2" "$3")" >&3; fi
}
# ok ID RU EN — a passed check.
ok() {
  if [ "$EVENTS" = 1 ]; then event_line ok id "$1" "$(pick "$2" "$3")"
  else printf '  ✓ %s\n' "$(pick "$2" "$3")" >&3; fi
}
# die CODE RU EN — stop with an error. CODE is stable: the app maps it to its own text and help.
DATA=""   # extra JSON fields for the error event, e.g. "serverIP":"…"
die() {
  if [ "$EVENTS" = 1 ]; then
    local extra
    extra=$(detail_field)
    [ -z "$DATA" ] || extra="${extra:+$extra,}$DATA"
    event_line error code "$1" "$(pick "$2" "$3")" "$extra"
  else
    [ -z "$DETAIL" ] || printf '%s\n' "$DETAIL" >&3
    printf '\n✗ %s\n' "$(pick "$2" "$3")" >&3
  fi
  exit 1
}
# Extras (BBR, fail2ban, updates) never stop the install: they warn, and the warnings are repeated at the end.
WARNINGS=()
WARNING_IDS=()
# warn ID RU EN
warn() {
  local m
  m=$(pick "$2" "$3")
  WARNINGS+=("$m"); WARNING_IDS+=("$1")
  if [ "$EVENTS" = 1 ]; then event_line warn id "$1" "$m" "$(detail_field)"
  else
    [ -z "$DETAIL" ] || printf '%s\n' "$DETAIL" >&3
    printf '! %s\n' "$m" >&3
  fi
  DETAIL=""
}

# Any command that fails where the script didn't expect it: say so instead of exiting silently.
on_error() {
  local rc=$1 line=$2
  # In a subshell or command substitution just pass the failure up; the main shell reports it once.
  [ "$BASHPID" = "$$" ] || exit "$rc"
  trap - ERR
  # With --events, the failed command's own message is in the log; send its tail along.
  [ -z "$ERRLOG" ] || DETAIL=$(tail -c 2000 "$ERRLOG" 2>/dev/null || true)
  die unexpected "Неожиданная ошибка (код $rc, строка $line). Запустите скрипт ещё раз; если повторится, сообщите о проблеме." \
                 "Unexpected error (exit code $rc, line $line). Run the script again; if it happens again, report the problem."
}
trap 'on_error $? $LINENO' ERR
trap '[ -z "$ERRLOG" ] || rm -f "$ERRLOG"' EXIT

usage() {
  local u="Usage: server.sh --domain NAME [--new-password] [--no-bbr] [--no-fail2ban] [--no-auto-updates] [--json] [--events] [--lang ru|en] | --check [--domain NAME] | --status | --uninstall"
  if [ "$EVENTS" = 1 ]; then event_line error code usage "$u"; else echo "$u" >&3; fi
  exit 2
}

# --- Helpers --------------------------------------------------------------------------------------

APT_UPDATED=0
# Returns non-zero on failure and leaves apt's output in DETAIL; callers decide whether that's fatal.
apt_install() {
  # Fresh servers often run apt on first boot, so wait for the lock instead of failing.
  # apt's chatter (debconf notes and the like) is shown only when it fails.
  local log
  log=$(mktemp)
  if [ "$APT_UPDATED" = 0 ]; then
    if ! DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update -qq </dev/null >"$log" 2>&1; then
      DETAIL=$(tail -c 4000 "$log"); rm -f "$log"; return 1
    fi
    APT_UPDATED=1
  fi
  if ! DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y -qq "$@" </dev/null >"$log" 2>&1; then
    DETAIL=$(tail -c 4000 "$log"); rm -f "$log"; return 1
  fi
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

public_ipv4() {
  curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true
}

resolve_v4() { getent ahostsv4 "$1" | awk '{print $1}' | sort -u | tr '\n' ' ' || true; }

# Names of programs other than our Caddy listening on TCP 80 or 443 ("" when the ports are free).
busy_ports() {
  ss -tlnpH '( sport = :80 or sport = :443 )' | grep -v '"caddy"' | grep -o 'users:(("[^"]*"' | cut -d'"' -f2 | sort -u | paste -sd, - | sed 's/,/, /g' || true
}

foreign_caddy() { [ -f /etc/caddy/Caddyfile ] && ! grep -q forward_proxy /etc/caddy/Caddyfile; }
installed_domain() { [ -f /etc/caddy/Caddyfile ] && sed -n 's/^:443, \(.*\) {$/\1/p' /etc/caddy/Caddyfile | head -1 || true; }

os_supported() {
  case " ${ID:-} ${ID_LIKE:-} " in *" debian "*|*" ubuntu "*) return 0 ;; esac
  return 1
}

# --- Install --------------------------------------------------------------------------------------

preflight() {
  [ "$EVENTS" = 1 ] && event_line step id preflight "$(pick "Проверка сервера" "Checking the server")"
  [ "$(id -u)" = 0 ] || die not_root "Запустите от root: … | sudo bash -s -- --domain $DOMAIN" \
                                     "Run as root: … | sudo bash -s -- --domain $DOMAIN"
  [ -r /etc/os-release ] && . /etc/os-release
  os_supported || die unsupported_os "Нужен Debian или Ubuntu, а здесь ${PRETTY_NAME:-неизвестная ОС}." \
                                     "Debian or Ubuntu is required, this is ${PRETTY_NAME:-an unknown OS}."
  [ -d /run/systemd/system ] || die no_systemd "Нужен systemd." "systemd is required."
  [ "$(uname -m)" = x86_64 ] || die unsupported_arch "Нужен сервер x86_64 (amd64): для $(uname -m) готовой сборки Caddy с прокси нет." \
                                                     "An x86_64 (amd64) server is required: there is no ready Caddy proxy build for $(uname -m)."
  say "ОС: ${PRETTY_NAME:-?} ($(uname -m))" "OS: ${PRETTY_NAME:-?} ($(uname -m))"

  local missing=()
  command -v curl >/dev/null || missing+=(curl)
  command -v xz >/dev/null || missing+=(xz-utils)
  command -v openssl >/dev/null || missing+=(openssl)
  command -v ss >/dev/null || missing+=(iproute2)
  [ -f /etc/ssl/certs/ca-certificates.crt ] || missing+=(ca-certificates)
  [ ${#missing[@]} = 0 ] || apt_install "${missing[@]}" \
    || die apt_failed "Не удалось установить: ${missing[*]}" "Couldn't install: ${missing[*]}"
}

check_dns() {
  step dns "Проверка домена $DOMAIN" "Checking the domain $DOMAIN"
  SERVER_IP=$(public_ipv4)
  is_ipv4 "$SERVER_IP" || die no_ipv4 "Не удалось узнать внешний IPv4 сервера. Нужен сервер с публичным IPv4." \
                                      "Couldn't find the server's public IPv4. A server with a public IPv4 is required."
  local resolved
  resolved=$(resolve_v4 "$DOMAIN")
  say "сервер: $SERVER_IP, $DOMAIN → ${resolved:-нет записи}" "server: $SERVER_IP, $DOMAIN → ${resolved:-no record}"
  case " $resolved " in
    *" $SERVER_IP "*) ;;
    *)
      DATA="\"serverIP\":\"$SERVER_IP\",\"resolved\":[$(for ip in $resolved; do printf '"%s",' "$ip"; done | sed 's/,$//')]"
      die dns_mismatch "A-запись $DOMAIN должна указывать на $SERVER_IP. Исправьте её у регистратора или в DuckDNS и подождите пару минут." \
                       "The A record of $DOMAIN must point at $SERVER_IP. Fix it at your registrar or in DuckDNS and wait a couple of minutes." ;;
  esac
}

check_ports() {
  # Ports 80 (Let's Encrypt HTTP-01) and 443 must be free or already ours.
  local busy
  busy=$(busy_ports)
  if [ -n "$busy" ]; then
    DATA="\"programs\":$(json_str "$busy")"
    die ports_busy "Порты 80 и 443 заняты: ${busy}. Похоже, здесь уже работает веб-сервер или другая VPN-панель. Освободите порты или возьмите отдельный сервер." \
                   "Ports 80 and 443 are taken by: ${busy}. Looks like a web server or another VPN panel already runs here. Free the ports or use a separate server."
  fi
  # A Caddy we didn't set up serves someone's sites: don't overwrite its config.
  if foreign_caddy; then
    die foreign_caddy "На сервере уже есть Caddy со своими сайтами (/etc/caddy/Caddyfile). Скрипт его не трогает: возьмите отдельный сервер." \
                      "This server already runs Caddy with its own sites (/etc/caddy/Caddyfile). The script won't touch it: use a separate server."
  fi
}

open_firewall() {
  command -v ufw >/dev/null && ufw status 2>/dev/null | grep "Status: active" >/dev/null || return 0
  ufw allow 80/tcp >/dev/null && ufw allow 443/tcp >/dev/null && ufw allow 443/udp >/dev/null
  say "ufw: открыты порты 80 и 443" "ufw: opened ports 80 and 443"
}

install_caddy() {
  step caddy "Caddy $CADDY_VERSION" "Caddy $CADDY_VERSION"
  CADDY_CHANGED=0
  # No grep -q after a pipe: with pipefail an early exit turns into SIGPIPE for the writer.
  if ! /usr/local/bin/caddy version 2>/dev/null | grep "^${CADDY_VERSION%-naive} " >/dev/null; then
    local tmp
    tmp=$(mktemp -d)
    if ! DETAIL=$(curl -fsSL --retry 3 -o "$tmp/c.tar.xz" "https://github.com/klzgrad/forwardproxy/releases/download/$CADDY_VERSION/caddy-forwardproxy-naive.tar.xz" 2>&1); then
      rm -rf "$tmp"
      die download_failed "Не удалось скачать Caddy с GitHub. Проверьте, открывается ли github.com с сервера, и запустите скрипт ещё раз." \
                          "Couldn't download Caddy from GitHub. Check that the server can reach github.com and run the script again."
    fi
    DETAIL=""
    echo "$CADDY_SHA256  $tmp/c.tar.xz" | sha256sum -c --status \
      || { rm -rf "$tmp"; die checksum_mismatch "Контрольная сумма Caddy не совпала, установка остановлена." "Caddy checksum mismatch, stopping."; }
    tar -xJf "$tmp/c.tar.xz" -C "$tmp"
    install -m 0755 "$tmp/caddy-forwardproxy-naive/caddy" /usr/local/bin/caddy
    rm -rf "$tmp"
    CADDY_CHANGED=1
  fi
  /usr/local/bin/caddy list-modules | grep '^http.handlers.forward_proxy$' >/dev/null \
    || die no_forward_proxy "В сборке Caddy нет forward_proxy." "The Caddy build lacks forward_proxy."

  id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy
  install -d -m 0755 /etc/caddy /var/www/site

  if [ "$NEW_PASSWORD" = 1 ] || [ ! -f "$CREDS" ]; then
    local u p
    u="u$(openssl rand -hex 6)"
    p="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40)"
    ( umask 077; printf 'PROXY_USER=%s\nPROXY_PASS=%s\n' "$u" "$p" > "$CREDS" )
  fi
  # shellcheck source=/dev/null
  . "$CREDS"

  # Placeholder page: what anyone without the password sees.
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
  local verdict
  if ! verdict=$(/usr/local/bin/caddy validate --adapter caddyfile --config "$tmp_conf" 2>&1); then
    rm -f "$tmp_conf"
    DETAIL=$(printf '%s\n' "$verdict" | grep -v '^{' | tail -3; printf '%s\n' "$verdict" | grep -o '"error":"[^"]*"' | tail -1 || true)
    die caddy_rejected "Caddy не принял конфигурацию." "Caddy rejected the configuration."
  fi
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
    if ! systemctl restart caddy 2>/dev/null; then
      DETAIL=$(journalctl -u caddy -n 20 -o cat --no-pager 2>/dev/null | grep -v '^{' | tail -5 || true)
      die caddy_failed "Caddy не запустился, подробности: journalctl -u caddy -n 50" "Caddy didn't start, details: journalctl -u caddy -n 50"
    fi
    say "Caddy перезапущен" "Caddy restarted"
  else
    say "Caddy уже настроен, перезапуск не нужен" "Caddy is already set up, no restart needed"
  fi
}

setup_bbr() {
  [ "$BBR" = 1 ] || return 0
  step bbr "BBR" "BBR"
  # On a ~200 ms route BBR raised single-stream speed from ~0.5 to ~3 MB/s.
  # Container-based VPS (OpenVZ, LXC) can't change it: then the proxy simply goes without.
  modprobe tcp_bbr 2>/dev/null || true
  # Check the value, not the exit code: procps 3.3 (Ubuntu 22.04) reports success even when it fails.
  sysctl -q -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
  if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != bbr ]; then
    warn bbr "BBR на этом сервере недоступен (так бывает на VPS с контейнерной виртуализацией). Прокси работает и без него." \
             "BBR isn't available on this server (common on container-based VPS). The proxy works without it."
    return 0
  fi
  sysctl -q -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
  # 99-zz makes the file apply last at boot, after any hosting provider's tuning.
  local tmp
  tmp=$(mktemp); echo tcp_bbr > "$tmp"; put "$tmp" /etc/modules-load.d/bbr.conf 0644 || true
  tmp=$(mktemp); printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > "$tmp"
  put "$tmp" /etc/sysctl.d/99-zz-bbr.conf 0644 || true
  local dev
  dev=$(ip route show default | awk '{print $5; exit}')
  if [ -n "$dev" ] && ! tc qdisc show dev "$dev" | grep '^qdisc fq ' >/dev/null; then
    tc qdisc replace dev "$dev" root fq 2>/dev/null || true
  fi
  say "TCP: $(sysctl -n net.ipv4.tcp_congestion_control)" "TCP: $(sysctl -n net.ipv4.tcp_congestion_control)"
}

setup_fail2ban() {
  [ "$FAIL2BAN" = 1 ] || return 0
  step fail2ban "fail2ban для SSH" "fail2ban for SSH"
  local pkgs=()
  command -v fail2ban-client >/dev/null || pkgs+=(fail2ban)
  python3 -c 'import systemd.journal' 2>/dev/null || pkgs+=(python3-systemd)
  command -v nft >/dev/null || pkgs+=(nftables)
  if [ ${#pkgs[@]} != 0 ] && ! apt_install "${pkgs[@]}"; then
    warn fail2ban_install "fail2ban не установился, SSH остался без защиты от подбора пароля." "fail2ban didn't install, SSH is left without password-guessing protection."
    return 0
  fi

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
  if ! fail2ban-client -t >/dev/null 2>&1; then
    # Don't leave a config that keeps fail2ban from starting.
    rm -f /etc/fail2ban/jail.d/zz-routekeeper.local /etc/fail2ban/fail2ban.d/zz-routekeeper.local
    warn fail2ban_config "fail2ban не принял конфигурацию, SSH остался без защиты от подбора пароля." "fail2ban rejected the configuration, SSH is left without password-guessing protection."
    return 0
  fi
  systemctl enable -q fail2ban 2>/dev/null || true
  if [ "$changed" = 1 ] || ! systemctl is-active -q fail2ban; then systemctl restart fail2ban 2>/dev/null || true; fi
  for _ in $(seq 1 15); do fail2ban-client status sshd >/dev/null 2>&1 && break; sleep 1; done
  if ! fail2ban-client status sshd >/dev/null 2>&1; then
    warn fail2ban_jail "fail2ban не запустил защиту SSH (journalctl -u fail2ban покажет почему)." "fail2ban didn't start the SSH jail (journalctl -u fail2ban shows why)."
    return 0
  fi
  say "5 неудачных входов за час → бан на сутки, повторно дольше" "5 failed logins in an hour → banned for a day, longer for repeat offenders"
}

setup_auto_updates() {
  [ "$AUTO_UPDATES" = 1 ] || return 0
  step updates "Автоматические обновления безопасности" "Automatic security updates"
  if ! dpkg -s unattended-upgrades >/dev/null 2>&1 && ! apt_install unattended-upgrades; then
    warn updates "unattended-upgrades не установился, обновления безопасности придётся ставить вручную." "unattended-upgrades didn't install, security updates have to be applied by hand."
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > "$tmp"
  put "$tmp" /etc/apt/apt.conf.d/20auto-upgrades 0644 || true
  say "включены, сервер сам не перезагружается" "on, the server never reboots by itself"
}

verify() {
  step checks "Проверки" "Checks"
  # Talk to Caddy on this machine, so the checks don't depend on hairpin routing.
  local resolve=(--resolve "$DOMAIN:443:127.0.0.1")
  local reachable=0
  for _ in $(seq 1 45); do
    curl -fsS -o /dev/null --max-time 5 "${resolve[@]}" "https://$DOMAIN/" 2>/dev/null && { reachable=1; break; }
    sleep 2
  done
  if [ "$reachable" = 0 ]; then
    local reason
    reason=$(journalctl -u caddy -n 50 -o cat --no-pager 2>/dev/null | grep '"level":"error"' | tail -1 \
      | grep -oE '"error":"([^"\\]|\\.)*"' | head -1 | cut -c10-400 || true)
    [ -z "$reason" ] || DETAIL="Let's Encrypt: $reason"
    die cert_failed "Caddy не получил сертификат Let's Encrypt. Чаще всего порты 80 и 443 закрыты в панели хостера (firewall, security group): откройте их и запустите скрипт ещё раз." \
                    "Caddy couldn't get a Let's Encrypt certificate. Usually ports 80 and 443 are closed in the hosting panel (firewall, security group): open them and run the script again."
  fi
  ok cert "сертификат Let's Encrypt получен, сайт открывается" "Let's Encrypt certificate obtained, the site is up"

  # A single miss of an IP echo service shouldn't fail an install whose proxy works: retry, then fall back.
  local exit_ip="" url
  for _ in 1 2 3; do
    for url in https://api.ipify.org https://ifconfig.me; do
      exit_ip=$(curl -fsS --max-time 15 "${resolve[@]}" -x "https://$DOMAIN:443" -K - "$url" <<<"proxy-user = \"$PROXY_USER:$PROXY_PASS\"" 2>/dev/null || true)
      [ "$exit_ip" = "$SERVER_IP" ] && break 2
    done
    sleep 2
  done
  [ "$exit_ip" = "$SERVER_IP" ] || die proxy_check_failed "Прокси с паролем не работает (ответ: '${exit_ip}')." "The proxy doesn't work with the password (got '${exit_ip}')."
  ok proxy "прокси с паролем работает, внешний IP $SERVER_IP" "proxy works with the password, exit IP $SERVER_IP"

  local probe
  # %{http_connect} is the proxy's answer to CONNECT; %{http_code} stays 000 when the tunnel fails.
  probe=$(curl -s --max-time 10 -o /dev/null -w '%{http_connect}' "${resolve[@]}" -p -x "https://$DOMAIN:443" https://api.ipify.org 2>/dev/null || true)
  [ "$probe" != 407 ] || die probe_407 "Без пароля прокси отвечает 407, а должен отвечать как обычный веб-сервер." "Without the password the proxy answers 407 instead of a plain web server response."
  ok probe "без пароля прокси закрыт для посторонних" "without the password the proxy is closed to strangers"

  echo "$SCRIPT_VERSION" > "$MARKER"
}

# A JSON array of strings from the arguments.
json_array() {
  local out="" sep="" x
  for x in "$@"; do out+="$sep$(json_str "$x")"; sep=","; done
  printf '[%s]' "$out"
}

report() {
  local url="https://$PROXY_USER:$PROXY_PASS@$DOMAIN:443" w
  if [ ${#WARNINGS[@]} != 0 ] && [ "$EVENTS" = 0 ]; then
    say "" ""
    for w in "${WARNINGS[@]}"; do printf '! %s\n' "$w" >&3; done
  fi
  if [ "$JSON" = 1 ]; then
    printf '{"type":"https","host":"%s","port":443,"username":"%s","password":"%s","url":"%s","serverIP":"%s","caddy":"%s","script":%s,"warnings":%s,"warningIds":%s}\n' \
      "$DOMAIN" "$PROXY_USER" "$PROXY_PASS" "$url" "$SERVER_IP" "${CADDY_VERSION%-naive}" "$SCRIPT_VERSION" \
      "$(json_array ${WARNINGS[@]+"${WARNINGS[@]}"})" "$(json_array ${WARNING_IDS[@]+"${WARNING_IDS[@]}"})"
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
  [ "$(id -u)" = 0 ] || die not_root "Запустите от root." "Run as root."
  if foreign_caddy; then
    die uninstall_foreign "Caddy на этом сервере ставил не Routekeeper, удалять его скрипт не будет." "Caddy on this server wasn't set up by Routekeeper, the script won't remove it."
  fi
  step uninstall "Удаление прокси" "Removing the proxy"
  systemctl disable --now -q caddy 2>/dev/null || true
  rm -f /etc/systemd/system/caddy.service
  systemctl daemon-reload
  rm -rf /etc/caddy /var/www/site /var/lib/caddy /usr/local/bin/caddy
  userdel caddy 2>/dev/null || true
  say "Прокси удалён. BBR, fail2ban и автообновления остались: они полезны и без прокси." \
      "The proxy is removed. BBR, fail2ban and automatic updates stay: they're useful without the proxy too."
  [ "$JSON" = 0 ] || printf '{"removed":true}\n'
}

# --- Read-only modes for the app ------------------------------------------------------------------

# --check: does this server fit? Changes nothing, never stops at the first problem: lists them all.
check_only() {
  local issues=() root=false systemd=false installed=false os="" arch ipv4 domain_now
  add_issue() { issues+=("{\"code\":\"$1\",\"text\":$(json_str "$(pick "$2" "$3")")}"); }
  [ "$(id -u)" = 0 ] && root=true || add_issue not_root "Нужны права root (или sudo без пароля)." "Root rights are required (or sudo without a password)."
  [ -r /etc/os-release ] && . /etc/os-release
  os=${PRETTY_NAME:-}
  os_supported || add_issue unsupported_os "Нужен Debian или Ubuntu, а здесь ${PRETTY_NAME:-неизвестная ОС}." "Debian or Ubuntu is required, this is ${PRETTY_NAME:-an unknown OS}."
  [ -d /run/systemd/system ] && systemd=true || add_issue no_systemd "Нужен systemd." "systemd is required."
  arch=$(uname -m)
  [ "$arch" = x86_64 ] || add_issue unsupported_arch "Нужен сервер x86_64 (amd64), а здесь $arch." "An x86_64 (amd64) server is required, this is $arch."
  ipv4=""
  command -v curl >/dev/null && ipv4=$(public_ipv4)
  if command -v curl >/dev/null && ! is_ipv4 "$ipv4"; then
    add_issue no_ipv4 "Не удалось узнать внешний IPv4 сервера." "Couldn't find the server's public IPv4."
    ipv4=""
  fi
  if command -v ss >/dev/null; then
    local busy
    busy=$(busy_ports)
    [ -z "$busy" ] || add_issue ports_busy "Порты 80 и 443 заняты: ${busy}." "Ports 80 and 443 are taken by: ${busy}."
  fi
  foreign_caddy && add_issue foreign_caddy "На сервере уже есть Caddy со своими сайтами." "This server already runs Caddy with its own sites."
  domain_now=$(installed_domain)
  [ -z "$domain_now" ] || installed=true
  local dns="null"
  if [ -n "$DOMAIN" ]; then
    local resolved matches=false
    resolved=$(resolve_v4 "$DOMAIN")
    case " $resolved " in *" $ipv4 "*) [ -n "$ipv4" ] && matches=true ;; esac
    [ "$matches" = true ] || add_issue dns_mismatch "A-запись $DOMAIN не указывает на ${ipv4:-этот сервер}." "The A record of $DOMAIN doesn't point at ${ipv4:-this server}."
    # shellcheck disable=SC2086
    dns="{\"name\":$(json_str "$DOMAIN"),\"resolved\":$(json_array $resolved),\"matches\":$matches}"
  fi
  local list="" sep="" i
  for i in ${issues[@]+"${issues[@]}"}; do list+="$sep$i"; sep=","; done
  printf '{"ok":%s,"script":%s,"os":%s,"arch":%s,"root":%s,"systemd":%s,"ipv4":%s,"installed":%s,"domain":%s,"dns":%s,"issues":[%s]}\n' \
    "$([ ${#issues[@]} = 0 ] && echo true || echo false)" "$SCRIPT_VERSION" "$(json_str "$os")" "$(json_str "$arch")" \
    "$root" "$systemd" "$([ -n "$ipv4" ] && json_str "$ipv4" || echo null)" "$installed" \
    "$([ -n "$domain_now" ] && json_str "$domain_now" || echo null)" "$dns" "$list"
}

# --status: what the installed proxy looks like now.
status_only() {
  local domain caddy="absent" version="null" cert="null" f2b="absent" banned="null" bbr=false updates=false script="null"
  domain=$(installed_domain)
  if [ -n "$domain" ] && ! foreign_caddy; then
    caddy=$(systemctl is-active caddy 2>/dev/null || true)
    [ -n "$caddy" ] || caddy="unknown"
    local v
    v=$(/usr/local/bin/caddy version 2>/dev/null | awk '{print $1}' || true)
    [ -z "$v" ] || version=$(json_str "$v")
    local end
    end=$(timeout 8 openssl s_client -connect 127.0.0.1:443 -servername "$domain" </dev/null 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//' || true)
    [ -z "$end" ] || cert=$(json_str "$(date -u -d "$end" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$end")")
    [ ! -r "$MARKER" ] || script=$(tr -dc '0-9' < "$MARKER")
    [ -n "$script" ] || script="null"
  fi
  if command -v fail2ban-client >/dev/null; then
    f2b=$(systemctl is-active fail2ban 2>/dev/null || true)
    [ -n "$f2b" ] || f2b="unknown"
    local n
    n=$(fail2ban-client status sshd 2>/dev/null | sed -n 's/.*Currently banned:[[:space:]]*//p' || true)
    [ -z "$n" ] || banned=$n
  fi
  [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" = bbr ] && bbr=true
  grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null && updates=true
  printf '{"installed":%s,"domain":%s,"caddy":%s,"version":%s,"certNotAfter":%s,"script":%s,"latestScript":%s,"fail2ban":%s,"banned":%s,"bbr":%s,"updates":%s}\n' \
    "$([ -n "$domain" ] && ! foreign_caddy && echo true || echo false)" "$([ -n "$domain" ] && json_str "$domain" || echo null)" \
    "$(json_str "$caddy")" "$version" "$cert" "$script" "$SCRIPT_VERSION" "$(json_str "$f2b")" "$banned" "$bbr" "$updates"
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
      --events) EVENTS=1; shift ;;
      --check) CHECK=1; shift ;;
      --status) STATUS=1; shift ;;
      --lang) case "${2:-}" in ru) RU=1 ;; en) RU=0 ;; *) usage ;; esac; shift 2 ;;
      --uninstall) UNINSTALL=1; shift ;;
      -h|--help) usage ;;
      *) usage ;;
    esac
  done
  DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')
  if [ "$EVENTS" = 1 ]; then
    ERRLOG=$(mktemp)
    exec 2>>"$ERRLOG"
  fi
  if [ "$STATUS" = 1 ]; then status_only; return; fi
  if [ "$CHECK" = 1 ]; then check_only; return; fi
  if [ "$UNINSTALL" = 1 ]; then uninstall; return; fi
  [[ $DOMAIN =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] \
    || die bad_domain "Укажите домен: --domain my-name.duckdns.org" "Pass the domain: --domain my-name.duckdns.org"

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
