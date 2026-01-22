#!/bin/sh
set -e

# Create SSL directory
mkdir -p /etc/nginx/ssl

# Generate self-signed fallback certificate for default server
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/default-key.pem \
  -out /etc/nginx/ssl/default-cert.pem \
  -subj "/CN=_" 2>/dev/null

# Check if wildcard certificate exists
CERT_DIR="/etc/letsencrypt/live"
CERT_FOUND=0

if [ -d "$CERT_DIR" ] && [ -n "$(ls -A $CERT_DIR 2>/dev/null)" ]; then
  DOMAIN_DIR=$(ls -t $CERT_DIR | head -n 1)
  if [ -f "$CERT_DIR/$DOMAIN_DIR/fullchain.pem" ]; then
    echo "Certificate found in $DOMAIN_DIR, enabling HTTPS..."
    ln -sf "$CERT_DIR/$DOMAIN_DIR/fullchain.pem" /etc/nginx/ssl/cert.pem
    ln -sf "$CERT_DIR/$DOMAIN_DIR/privkey.pem" /etc/nginx/ssl/key.pem
    CERT_FOUND=1
  fi
fi

if [ $CERT_FOUND -eq 0 ]; then
  echo "No certificates found, running HTTP-only mode for ACME challenge..."
fi

# Start nginx in background
/docker-entrypoint.sh nginx -g 'daemon off;' &
NGINX_PID=$!

# Watch for new certificates and reload
(while :; do
  sleep 14400  # Check every 4 hours
  if [ $CERT_FOUND -eq 0 ] && [ -d "$CERT_DIR" ]; then
    DOMAIN_DIR=$(ls -t $CERT_DIR 2>/dev/null | head -n 1)
    if [ -n "$DOMAIN_DIR" ] && [ -f "$CERT_DIR/$DOMAIN_DIR/fullchain.pem" ]; then
      echo "Certificates obtained! Setting up HTTPS..."
      ln -sf "$CERT_DIR/$DOMAIN_DIR/fullchain.pem" /etc/nginx/ssl/cert.pem
      ln -sf "$CERT_DIR/$DOMAIN_DIR/privkey.pem" /etc/nginx/ssl/key.pem
      nginx -s reload
      echo "Nginx reloaded with HTTPS enabled"
      CERT_FOUND=1
    fi
  fi
done) &

wait $NGINX_PID
