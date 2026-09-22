#!/bin/sh
set -e

# Create SSL directory
mkdir -p /etc/nginx/ssl

# Wait for certificate to exist before starting nginx
CERT_DIR="/etc/letsencrypt/live"
CERT_FOUND=0

echo "Waiting for certificates..."
while [ $CERT_FOUND -eq 0 ]; do
  if [ -d "$CERT_DIR" ]; then
    for dir in "$CERT_DIR"/*/; do
      if [ -d "$dir" ] && [ -f "$dir/fullchain.pem" ] && [ -f "$dir/privkey.pem" ]; then
        DOMAIN_DIR=$(basename "$dir")
        echo "Certificate found in $DOMAIN_DIR, enabling HTTPS..."
        ln -sf "$CERT_DIR/$DOMAIN_DIR/fullchain.pem" /etc/nginx/ssl/cert.pem
        ln -sf "$CERT_DIR/$DOMAIN_DIR/privkey.pem" /etc/nginx/ssl/key.pem
        CERT_FOUND=1
        break
      fi
    done
  fi
  if [ $CERT_FOUND -eq 0 ]; then
    sleep 10
  fi
done

# Start nginx in background
/docker-entrypoint.sh nginx -g 'daemon off;' &
NGINX_PID=$!

# Watch for certificate renewals and reload nginx when the cert changes.
# set +e so a single failed reload (e.g. a broken conf.d file) doesn't kill the watcher for good.
(set +e
last_cert=$(readlink -f /etc/nginx/ssl/cert.pem)
while :; do
  sleep 3600  # Check every hour
  current_cert=$(readlink -f /etc/nginx/ssl/cert.pem)
  if [ "$current_cert" != "$last_cert" ]; then
    echo "Certificate changed ($last_cert -> $current_cert), reloading nginx..."
    if nginx -t && nginx -s reload; then
      echo "Nginx reloaded with updated certificate"
      last_cert=$current_cert
    else
      echo "Nginx reload failed, will retry next hour"
    fi
  fi
done) &

wait $NGINX_PID
