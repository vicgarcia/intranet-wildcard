#!/bin/sh
set -e

CERT_DIR="/etc/letsencrypt/live"
CHECK_INTERVAL=900  # 15 minutes

log() {
  echo "[cert-watch $(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

# Echo the newest lineage directory under live/, by fullchain.pem mtime.
# Certbot creates a new lineage (e.g. example.com-0001) when the domain list
# changes, so we re-scan every cycle rather than pinning the first match.
newest_lineage() {
  newest=""
  newest_time=0
  for dir in "$CERT_DIR"/*/; do
    [ -f "$dir/fullchain.pem" ] && [ -f "$dir/privkey.pem" ] || continue
    mtime=$(stat -L -c %Y "$dir/fullchain.pem" 2>/dev/null) || continue
    if [ "$mtime" -gt "$newest_time" ]; then
      newest_time=$mtime
      newest=$dir
    fi
  done
  [ -n "$newest" ] && basename "$newest"
}

# Point /etc/nginx/ssl at the given lineage.
link_cert() {
  ln -sf "$CERT_DIR/$1/fullchain.pem" /etc/nginx/ssl/cert.pem
  ln -sf "$CERT_DIR/$1/privkey.pem" /etc/nginx/ssl/key.pem
}

# Identity of the cert currently linked: resolved archive path plus mtime, so
# both a new lineage and a renewal in place register as a change.
cert_fingerprint() {
  target=$(readlink -f /etc/nginx/ssl/cert.pem 2>/dev/null) || return 0
  [ -n "$target" ] || return 0
  echo "$target:$(stat -L -c %Y "$target" 2>/dev/null)"
}

mkdir -p /etc/nginx/ssl

# The catch-all server in nginx.conf needs a certificate to terminate TLS before
# it can return 444, but it's never presented to a real client. Generate a
# throwaway self-signed pair when missing; /etc/nginx/ssl is container-local, so
# this runs on every fresh container.
if [ ! -f /etc/nginx/ssl/default-cert.pem ] || [ ! -f /etc/nginx/ssl/default-key.pem ]; then
  log "generating self-signed certificate for the default server"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/nginx/ssl/default-key.pem \
    -out /etc/nginx/ssl/default-cert.pem \
    -days 3650 -subj "/CN=invalid" >/dev/null 2>&1
  chmod 600 /etc/nginx/ssl/default-key.pem
fi

log "waiting for certificates in $CERT_DIR..."
while :; do
  LINEAGE=$(newest_lineage)
  if [ -n "$LINEAGE" ]; then
    log "certificate found in $LINEAGE, enabling HTTPS"
    link_cert "$LINEAGE"
    break
  fi
  sleep 10
done

# Start nginx in background
/docker-entrypoint.sh nginx -g 'daemon off;' &
NGINX_PID=$!

# Watch for renewals and reload nginx when the certificate changes. Runs with
# set +e so one failed reload (e.g. a conf.d file mid-edit) can't kill the
# watcher for the life of the container.
(
  set +e
  last=$(cert_fingerprint)
  log "watcher started, polling every ${CHECK_INTERVAL}s (current: ${last:-none})"
  while :; do
    sleep "$CHECK_INTERVAL"
    lineage=$(newest_lineage)
    [ -n "$lineage" ] && link_cert "$lineage"
    current=$(cert_fingerprint)
    if [ -z "$current" ]; then
      log "no certificate currently linked, skipping"
      continue
    fi
    if [ "$current" = "$last" ]; then
      log "no change ($current)"
      continue
    fi
    log "certificate changed: ${last:-none} -> $current, reloading nginx"
    if nginx -t && nginx -s reload; then
      log "nginx reloaded"
      last=$current
    else
      log "nginx reload FAILED, retrying in ${CHECK_INTERVAL}s"
    fi
  done
) &

wait $NGINX_PID
