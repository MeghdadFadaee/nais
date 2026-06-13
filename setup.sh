#!/bin/sh

set -eu

BASE_URL=${NAIS_BASE_URL:-https://meghdadfadaee.github.io/nais}
DEFAULT_ASSETS_PATH=/var/www/nais-assets
MANAGED_INCLUDE='include nais-sites/*.conf;'

say() {
    printf '%s\n' "$*"
}

fail() {
    printf 'nais setup: %s\n' "$*" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

prompt() {
    prompt_text=$1
    default_value=${2-}

    if [ -n "$default_value" ]; then
        printf '%s [%s]: ' "$prompt_text" "$default_value" >/dev/tty
    else
        printf '%s: ' "$prompt_text" >/dev/tty
    fi

    IFS= read -r answer </dev/tty || fail "could not read input from /dev/tty"
    if [ -z "$answer" ]; then
        answer=$default_value
    fi
    printf '%s' "$answer"
}

validate_absolute_path() {
    value=$1
    label=$2
    case "$value" in
        /*) ;;
        *) fail "$label must be an absolute path" ;;
    esac
    case "$value" in
        *'
'*) fail "$label must not contain newlines" ;;
    esac
}

nginx_quote() {
    value=$1
    case "$value" in
        *'"'*|*'\'*|*'$'*) fail "paths containing quotes, backslashes, or dollar signs are not supported" ;;
    esac
    printf '"%s"' "$value"
}

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM

    if [ "$status" -ne 0 ] && [ "${TRANSACTION_ACTIVE:-0}" -eq 1 ]; then
        restore_previous
    fi

    if [ -n "${WORK_DIR:-}" ]; then
        rm -rf "$WORK_DIR"
    fi
    exit "$status"
}

restore_previous() {
    say "Setup failed; restoring the previous nginx configuration and assets."
    set +e

    if [ "$SITE_EXISTED" -eq 1 ]; then
        run_root cp "$SITE_BACKUP" "$SITE_CONFIG"
    else
        run_root rm -f "$SITE_CONFIG"
    fi

    if [ "$MAIN_CHANGED" -eq 1 ]; then
        run_root cp "$MAIN_BACKUP" "$NGINX_CONF"
    fi

    for asset in autoindex.css autoindex.js favicon.ico; do
        if [ -f "$WORK_DIR/assets-backup/$asset" ]; then
            run_root cp "$WORK_DIR/assets-backup/$asset" "$ASSETS_PATH/$asset"
        else
            run_root rm -f "$ASSETS_PATH/$asset"
        fi
    done

    if ! run_root "$NGINX_BIN" -t; then
        printf '%s\n' "nais setup: rollback completed, but the restored nginx configuration is invalid" >&2
    fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if ! ( : </dev/tty && : >/dev/tty ) 2>/dev/null; then
    fail "/dev/tty is required for interactive setup"
fi
need_command curl
need_command nginx
need_command awk
need_command sed
need_command mktemp

if [ "$(id -u)" -ne 0 ]; then
    need_command sudo
    sudo -v || fail "root privileges are required to configure nginx"
fi

SERVER_NAME=$(prompt "Server name")
[ -n "$SERVER_NAME" ] || fail "server_name is required"
case "$SERVER_NAME" in
    *[!A-Za-z0-9._:-]*) fail "server_name must be one hostname or IP address without whitespace" ;;
esac

ROOT_PATH=$(prompt "Root path")
[ -n "$ROOT_PATH" ] || fail "root_path is required"
validate_absolute_path "$ROOT_PATH" "root_path"

ASSETS_PATH=$(prompt "Assets path" "$DEFAULT_ASSETS_PATH")
validate_absolute_path "$ASSETS_PATH" "assets_path"

CERTIFICATES_PATH=$(prompt "Certificates path (optional)")
if [ -n "$CERTIFICATES_PATH" ]; then
    validate_absolute_path "$CERTIFICATES_PATH" "certificates_path"
    run_root test -f "$CERTIFICATES_PATH/fullchain.pem" ||
        fail "certificate not found: $CERTIFICATES_PATH/fullchain.pem"
    run_root test -f "$CERTIFICATES_PATH/privkey.pem" ||
        fail "certificate key not found: $CERTIFICATES_PATH/privkey.pem"
fi

NGINX_BIN=$(command -v nginx)
NGINX_VERSION=$("$NGINX_BIN" -V 2>&1)
NGINX_PREFIX=$(printf '%s\n' "$NGINX_VERSION" | sed -n 's/.*--prefix=\([^ ]*\).*/\1/p')
NGINX_CONF=$(printf '%s\n' "$NGINX_VERSION" | sed -n 's/.*--conf-path=\([^ ]*\).*/\1/p')
[ -n "$NGINX_PREFIX" ] || NGINX_PREFIX=/etc/nginx
[ -n "$NGINX_CONF" ] || NGINX_CONF=$NGINX_PREFIX/conf/nginx.conf

case "$NGINX_CONF" in
    /*) ;;
    *) NGINX_CONF=$NGINX_PREFIX/$NGINX_CONF ;;
esac
run_root test -f "$NGINX_CONF" || fail "nginx configuration not found: $NGINX_CONF"

WORK_DIR=$(mktemp -d)
SITE_BACKUP=$WORK_DIR/site.conf.backup
MAIN_BACKUP=$WORK_DIR/nginx.conf.backup
GENERATED_CONFIG=$WORK_DIR/nais.conf
MAIN_CURRENT=$WORK_DIR/nginx.conf.current
MAIN_CHANGED=0
MAIN_NEEDS_CHANGE=0
SITE_EXISTED=0
TRANSACTION_ACTIVE=0
run_root cp "$NGINX_CONF" "$MAIN_CURRENT"
run_root chmod a+r "$MAIN_CURRENT"

say "Downloading NAIS assets..."
for asset in autoindex.css autoindex.js favicon.ico; do
    curl -fsSL "$BASE_URL/$asset" -o "$WORK_DIR/$asset" ||
        fail "failed to download $BASE_URL/$asset"
done

ROOT_QUOTED=$(nginx_quote "$ROOT_PATH")
ASSETS_QUOTED=$(nginx_quote "$ASSETS_PATH")

if [ -n "$CERTIFICATES_PATH" ]; then
    CERT_QUOTED=$(nginx_quote "$CERTIFICATES_PATH/fullchain.pem")
    KEY_QUOTED=$(nginx_quote "$CERTIFICATES_PATH/privkey.pem")
    cat >"$GENERATED_CONFIG" <<EOF
# Managed by NAIS setup.sh. Re-running setup replaces this file.
server {
    listen 443 ssl;
    server_name $SERVER_NAME;

    ssl_certificate $CERT_QUOTED;
    ssl_certificate_key $KEY_QUOTED;

    root $ROOT_QUOTED;

    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        sub_filter '</head>' '<link rel="stylesheet" href="/autoindex.css">';
        sub_filter '</body>' '<script src="/autoindex.js"></script></body>';
        sub_filter_once on;
    }

    location = /autoindex.css { root $ASSETS_QUOTED; }
    location = /autoindex.js { root $ASSETS_QUOTED; }
    location = /favicon.ico { root $ASSETS_QUOTED; }
}

server {
    listen 80;
    server_name $SERVER_NAME;
    return 301 https://$SERVER_NAME\$request_uri;
}
EOF
else
    cat >"$GENERATED_CONFIG" <<EOF
# Managed by NAIS setup.sh. Re-running setup replaces this file.
server {
    listen 80;
    server_name $SERVER_NAME;
    root $ROOT_QUOTED;

    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        sub_filter '</head>' '<link rel="stylesheet" href="/autoindex.css">';
        sub_filter '</body>' '<script src="/autoindex.js"></script></body>';
        sub_filter_once on;
    }

    location = /autoindex.css { root $ASSETS_QUOTED; }
    location = /autoindex.js { root $ASSETS_QUOTED; }
    location = /favicon.ico { root $ASSETS_QUOTED; }
}
EOF
fi

ACTIVE_INCLUDE=$(
    sed 's/[[:space:]]*#.*$//' "$MAIN_CURRENT" |
        awk '
            $1 == "include" {
                path = $2
                sub(/;$/, "", path)
                gsub(/^"|"$/, "", path)
                if (path ~ /sites-enabled\/\*$/) { print path; exit }
                if (path ~ /conf\.d\/\*\.conf$/) { print path; exit }
                if (path ~ /http\.d\/\*\.conf$/) { print path; exit }
                if (path ~ /nais-sites\/\*\.conf$/) { print path; exit }
            }
        '
)

if [ -n "$ACTIVE_INCLUDE" ]; then
    case "$ACTIVE_INCLUDE" in
        /*) INCLUDE_PATTERN=$ACTIVE_INCLUDE ;;
        *) INCLUDE_PATTERN=$NGINX_PREFIX/$ACTIVE_INCLUDE ;;
    esac
    SITE_DIR=${INCLUDE_PATTERN%/*}
else
    SITE_DIR=$NGINX_PREFIX/nais-sites
    cp "$MAIN_CURRENT" "$MAIN_BACKUP"
    awk -v include_line="    $MANAGED_INCLUDE" '
        BEGIN { added = 0 }
        !added && $0 ~ /^[[:space:]]*http[[:space:]]*\{/ {
            print
            print include_line
            added = 1
            next
        }
        { print }
        END {
            if (!added) exit 42
        }
    ' "$MAIN_CURRENT" >"$WORK_DIR/nginx.conf" ||
        fail "could not find the nginx http block in $NGINX_CONF"
    MAIN_NEEDS_CHANGE=1
fi

SITE_CONFIG=$SITE_DIR/nais.conf
run_root mkdir -p "$ROOT_PATH" "$ASSETS_PATH" "$SITE_DIR"
mkdir -p "$WORK_DIR/assets-backup"

for asset in autoindex.css autoindex.js favicon.ico; do
    if run_root test -e "$ASSETS_PATH/$asset" && ! run_root test -f "$ASSETS_PATH/$asset"; then
        fail "asset destination is not a regular file: $ASSETS_PATH/$asset"
    fi
    if run_root test -f "$ASSETS_PATH/$asset"; then
        run_root cp "$ASSETS_PATH/$asset" "$WORK_DIR/assets-backup/$asset"
    fi
done

if run_root test -e "$SITE_CONFIG"; then
    run_root test -f "$SITE_CONFIG" || fail "site config destination is not a regular file: $SITE_CONFIG"
    run_root cp "$SITE_CONFIG" "$SITE_BACKUP"
    SITE_EXISTED=1
fi

TRANSACTION_ACTIVE=1
run_root chmod a+rx "$ASSETS_PATH"
for asset in autoindex.css autoindex.js favicon.ico; do
    run_root cp "$WORK_DIR/$asset" "$ASSETS_PATH/$asset"
    run_root chmod a+r "$ASSETS_PATH/$asset"
done
run_root cp "$GENERATED_CONFIG" "$SITE_CONFIG"
if [ "$MAIN_NEEDS_CHANGE" -eq 1 ]; then
    MAIN_CHANGED=1
    run_root cp "$WORK_DIR/nginx.conf" "$NGINX_CONF"
fi

say "Validating nginx configuration..."
if ! run_root "$NGINX_BIN" -t; then
    fail "nginx validation failed"
fi

if command -v systemctl >/dev/null 2>&1; then
    if run_root systemctl is-active --quiet nginx; then
        run_root systemctl reload nginx
    else
        run_root systemctl enable --now nginx
    fi
elif command -v service >/dev/null 2>&1; then
    run_root service nginx restart
else
    fail "nginx configuration is installed, but no supported service manager was found"
fi

TRANSACTION_ACTIVE=0
say "NAIS configured successfully."
say "Site config: $SITE_CONFIG"
say "Assets: $ASSETS_PATH"
