#!/bin/sh
# One-time TLS bootstrap for the dev-vault stack (Nginx + certbot / Let's Encrypt).
#
# Solves the chicken-and-egg problem: nginx won't start without a certificate,
# but the certificate can't be issued without nginx answering the ACME challenge.
# Steps: dummy self-signed cert -> start nginx -> replace with a real cert -> reload.
#
# Run ONCE on the server, after `cp .env.example .env` (set DOMAIN + CERTBOT_EMAIL)
# and after DNS A-records api/app/admin point to this host:
#   chmod +x init-letsencrypt.sh && ./init-letsencrypt.sh
#
# Tip: set STAGING=1 the first time to use Let's Encrypt's staging CA and avoid
# hitting rate limits while you debug, then re-run without it for a trusted cert.
set -eu

COMPOSE="docker compose -f compose.prod.yml"

DOMAIN=$(grep -E '^DOMAIN=' .env | cut -d= -f2-)
CERTBOT_EMAIL=$(grep -E '^CERTBOT_EMAIL=' .env | cut -d= -f2-)
: "${DOMAIN:?DOMAIN is not set in .env}"
: "${CERTBOT_EMAIL:?CERTBOT_EMAIL is not set in .env}"

CERT_NAME="api.$DOMAIN"
LIVE_PATH="/etc/letsencrypt/live/$CERT_NAME"
DOMAIN_ARGS="-d api.$DOMAIN -d app.$DOMAIN -d admin.$DOMAIN"

STAGING_ARG=""
[ "${STAGING:-0}" = "1" ] && STAGING_ARG="--staging"

echo "### 1/5 Creating a dummy certificate so nginx can start ..."
$COMPOSE run --rm --entrypoint "\
  sh -c 'mkdir -p $LIVE_PATH && \
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout $LIVE_PATH/privkey.pem \
    -out    $LIVE_PATH/fullchain.pem \
    -subj   /CN=localhost'" certbot

echo "### 2/5 Starting nginx ..."
$COMPOSE up -d nginx

echo "### 3/5 Removing the dummy certificate ..."
$COMPOSE run --rm --entrypoint "\
  rm -rf /etc/letsencrypt/live/$CERT_NAME \
         /etc/letsencrypt/archive/$CERT_NAME \
         /etc/letsencrypt/renewal/$CERT_NAME.conf" certbot

echo "### 4/5 Requesting the real Let's Encrypt certificate ..."
$COMPOSE run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $STAGING_ARG \
    $DOMAIN_ARGS \
    --email $CERTBOT_EMAIL \
    --rsa-key-size 4096 \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    --force-renewal" certbot

echo "### 5/5 Reloading nginx with the real certificate ..."
$COMPOSE exec nginx nginx -s reload

echo "### Done. Bring the whole stack up with:"
echo "    $COMPOSE up -d --build"
