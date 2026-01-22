#!/bin/sh

trap exit TERM

echo "Certbot starting..."
sleep 10

# Create in-memory logs directory (logs will still go to stdout/stderr with -v)
mkdir -p /tmp/certbot-logs

# Check if certificate already exists
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "No certificate found for $DOMAIN, obtaining wildcard certificate..."
  staging_flag=""
  if [ "$CERT_STAGING" = "1" ]; then
    staging_flag="--staging"
    echo "Using Let's Encrypt staging server"
  fi

  certbot certonly \
    --authenticator dns-namecheap \
    --dns-namecheap-credentials /namecheap-credentials.ini \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    --non-interactive \
    --email $CERT_EMAIL \
    --logs-dir /tmp/certbot-logs \
    -v \
    $staging_flag \
    -d "$DOMAIN" \
    -d "*.$DOMAIN" && \
  echo "Wildcard certificate obtained successfully!" || \
  echo "Failed to obtain certificate. Check credentials and DNS settings."
else
  echo "Certificate already exists for $DOMAIN"
fi

# Check for renewal every day at 2 AM
while :; do
  sleep $(( (2*3600 - ($(date +%s) % 86400) + 86400) % 86400 ))
  echo "Checking for certificate renewal..."
  certbot renew \
    --authenticator dns-namecheap \
    --dns-namecheap-credentials /namecheap-credentials.ini \
    --logs-dir /tmp/certbot-logs \
    -v \
    --deploy-hook "echo 'Certificate renewed! Nginx will auto-reload.'"
done
