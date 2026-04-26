#!/bin/sh

trap exit TERM

echo "Certbot starting..."
sleep 10

# Create in-memory logs directory (logs will still go to stdout/stderr with -v)
mkdir -p /tmp/certbot-logs /tmp/certbot-work

# Parse comma-separated domains into -d flags
domain_flags=""
IFS=','
for domain in $DOMAINS; do
  domain=$(echo "$domain" | xargs)
  if [ -n "$domain" ]; then
    domain_flags="$domain_flags -d $domain"
  fi
done
unset IFS

# Extract the first domain for the certificate directory name
first_domain=$(echo "$DOMAINS" | cut -d',' -f1 | xargs)

# Check if certificate already exists
if [ ! -d "/etc/letsencrypt/live/$first_domain" ]; then
  echo "No certificate found for $first_domain, obtaining certificate for: $DOMAINS"
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
    --work-dir /tmp/certbot-work \
    -v \
    $staging_flag \
    $domain_flags && \
  echo "Certificate obtained successfully for: $DOMAINS" || \
  echo "Failed to obtain certificate. Check credentials and DNS settings."
else
  echo "Certificate already exists for $first_domain"
fi

# Check for renewal every day at 2 AM
while :; do
  sleep $(( (2*3600 - ($(date +%s) % 86400) + 86400) % 86400 ))
  echo "Checking for certificate renewal..."
  certbot renew \
    --authenticator dns-namecheap \
    --dns-namecheap-credentials /namecheap-credentials.ini \
    --logs-dir /tmp/certbot-logs \
    --work-dir /tmp/certbot-work \
    -v \
    --deploy-hook "echo 'Certificate renewed! Nginx will auto-reload.'"
done
