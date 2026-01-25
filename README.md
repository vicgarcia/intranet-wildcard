I run a home server with a bunch of dockerized web apps - Open Drone Map, Homebridge, Open WebUI, and more. These services live on a private network (not internet-accessible), but I use local DNS on my router to access them by hostname. HTTP isn't great on most modern browsers.

This setup uses Let's Encrypt with the DNS-01 challenge via Namecheap's API to automatically generate and renew SSL certificate. No HTTP challenge needed, which is perfect for private networks. The nginx container serves everything with valid SSL and proxies requests to localhost ports where other dockerized apps are listening.

## Setup

```bash
# Clone and configure
git clone git@github.com:vicgarcia/intranet-wildcard.git
cd intranet-wildcard

# Set your domain(s) and email
cp .env.example .env
nano .env  # Edit DOMAINS and CERT_EMAIL

# Add Namecheap API credentials
# Get these from https://ap.www.namecheap.com/settings/tools/apiaccess/
cp certbot/namecheap-credentials.ini.example certbot/namecheap-credentials.ini
nano certbot/namecheap-credentials.ini  # Add your username and API key

# Create nginx configs for your apps
# Copy nginx/conf.d/app.conf.example for each service
# Point each one to host.docker.internal:PORT where your app listens

# Start it up
docker compose up -d
```

## How It Works

**Certificates**: Certbot uses the Namecheap DNS plugin to create TXT records for Let's Encrypt's DNS-01 challenge. This lets you get wildcard certs (`*.yourdomain.com`) even when your server isn't publicly accessible. Certificates renew automatically.

**Proxying**: Nginx terminates SSL and proxies to your apps via `host.docker.internal:PORT`. Each of your other docker stacks should publish to `127.0.0.1:PORT:CONTAINER_PORT` to keep them locked down—only accessible through nginx.

**Example app configuration**:

```yaml
# Your app's docker-compose.yml
services:
  myapp:
    image: myapp
    ports:
      - "127.0.0.1:8001:3000"  # Only accessible from localhost
```

```nginx
# nginx/conf.d/myapp.conf
upstream myapp_backend {
    server host.docker.internal:8001;
}

server {
    listen 443 ssl;
    server_name myapp.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://myapp_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Testing

Start with staging certificates to avoid hitting Let's Encrypt rate limits:

```bash
# In .env, set:
CERT_STAGING=1

docker compose up -d
docker compose logs -f certbot

# Once it works, switch to production
CERT_STAGING=0

docker compose down
rm -rf certbot/letsencrypt/*
docker compose up -d
```

## Logs

All logs go to Docker:

```bash
docker compose logs -f nginx
docker compose logs -f certbot
```

## Troubleshooting

**Check certificate status:**
```bash
docker compose exec nginx ls -la /etc/letsencrypt/live/
```

**Reload nginx after config changes:**
```bash
docker compose exec nginx nginx -t  # Test config
docker compose exec nginx nginx -s reload
```

**Force certificate renewal:**
```bash
docker compose exec certbot certbot renew --force-renewal --logs-dir /tmp/certbot-logs -v
docker compose restart nginx
```

## Security Notes

- Use `127.0.0.1:PORT:PORT` for all app port mappings to prevent direct access
- The `certbot/namecheap-credentials.ini` file contains your API key—it's gitignored, keep it that way
- DNS-01 challenge means you don't need ports 80/443 open to the internet
