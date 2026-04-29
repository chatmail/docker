#!/bin/bash
# Dump diagnostic info for chatmail services inside the container
# Usage: get_service_logs [service...]

set -euo pipefail

core_services="dovecot postfix nginx filtermail filtermail-incoming opendkim unbound doveauth chatmail-metadata"
optional_services="iroh-relay turnserver mtail"

if [ $# -gt 0 ]; then
    services="$*"
else
    services="$core_services"
    for svc in $optional_services; do
        systemctl is-enabled "$svc" 2>/dev/null && services="$services $svc"
    done
fi

for svc in $services; do
    echo "=== journalctl -u $svc ==="
    journalctl -u "$svc" --no-pager -n 50 2>&1 || true
    echo
done

echo "=== failed units ==="
systemctl --failed --no-pager 2>&1 || true
echo

echo "=== dovecot -n (effective config) ==="
dovecot -n 2>&1 | tail -40 || true
echo

echo "=== TLS certificates ==="
ini="${CHATMAIL_INI:-/etc/chatmail/chatmail.ini}"
if ext=$(grep '^tls_external_cert_and_key' "$ini" 2>/dev/null); then
    echo "$ext" | awk -F= '{print $2}' | xargs -n1 ls -la 2>&1 || true
elif [ -f /var/lib/acme/live/*/fullchain ] 2>/dev/null; then
    ls -la /var/lib/acme/live/*/fullchain /var/lib/acme/live/*/privkey 2>&1 || true
else
    # self-signed fallback
    ls -la /etc/ssl/certs/mailserver.pem /etc/ssl/private/mailserver.key 2>&1 || true
fi
