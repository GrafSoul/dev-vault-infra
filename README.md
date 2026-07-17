# dev-vault-infra

Production orchestration for **dev-vault**: three independently developed apps
served on their own subdomains behind an Nginx reverse proxy with TLS from
Let's Encrypt (certbot).

## The dev-vault project

**dev-vault** is split into four repositories, developed and deployed independently:

| Repository                                                       | Role                                       | Local dev               |
| ---------------------------------------------------------------- | ------------------------------------------ | ----------------------- |
| [dev-vault-server](https://github.com/GrafSoul/dev-vault-server) | Backend API (NestJS)                       | `http://localhost:3030` |
| [dev-vault-client](https://github.com/GrafSoul/dev-vault-client) | Client SPA (React + Vite)                  | `http://localhost:3000` |
| [dev-vault-admin](https://github.com/GrafSoul/dev-vault-admin)   | Admin SPA (React + Vite)                   | `http://localhost:3001` |
| [dev-vault-infra](https://github.com/GrafSoul/dev-vault-infra)   | Production orchestration (Nginx + certbot) | —                       |

## Architecture

```text
Browser ──HTTPS──▶ Nginx (80/443, TLS via certbot)
                     api.YOUR_DOMAIN    → backend  (NestJS, :3030)
                     app.YOUR_DOMAIN    → client   (static via nginx, :80)
                     admin.YOUR_DOMAIN  → admin    (static via nginx, :80)

backend ──private──▶ postgres (:5432) · redis (:6379)   # not exposed to the internet
```

Only Nginx publishes ports (80/443). Postgres and Redis have no public ports and
are reachable only over the private Docker network. One TLS certificate covers all
three subdomains; certbot renews it automatically.

## Layout

```text
dev-vault-infra/
├── compose.dev.yml            # local: all apps + Postgres + Redis (dev stages)
├── compose.prod.yml           # server: built images + Nginx + certbot
├── init-letsencrypt.sh        # one-time TLS bootstrap (issue the first cert)
├── nginx/
│   ├── templates/
│   │   └── default.conf.template   # reverse proxy (${DOMAIN} filled at startup)
│   └── snippets/
│       ├── ssl-params.conf         # TLS hardening + security headers (shared)
│       └── proxy.conf              # common proxy headers (shared)
├── .env.example
└── README.md
```

## Prerequisites

- A host with [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- A real domain with DNS A-records `api` / `app` / `admin` pointing to the host IP
- Ports 80 and 443 open

## Local development

Two ways to run the stack locally — pick one.

**A. Standalone (no Docker).** Each app runs independently on `localhost`:

```bash
# terminal 1
cd dev-vault-server && npm run start:dev    # http://localhost:3030
# terminal 2
cd dev-vault-client && npm run dev          # http://localhost:3000
# terminal 3
cd dev-vault-admin  && npm run dev          # http://localhost:3001
```

**B. One command (Docker).** Bring up all three apps + Postgres + Redis together:

```bash
cd dev-vault-infra
docker compose -f compose.dev.yml up
```

The frontends read `VITE_API_URL=http://localhost:3030` from their local `.env`.

> Dev and prod are deliberately separate files: `compose.dev.yml` for local work,
> `compose.prod.yml` for the server. Never run them together.

## Production deploy (single host, e.g. Hetzner)

```bash
# clone the four repos side by side
git clone https://github.com/GrafSoul/dev-vault-server.git
git clone https://github.com/GrafSoul/dev-vault-client.git
git clone https://github.com/GrafSoul/dev-vault-admin.git
git clone https://github.com/GrafSoul/dev-vault-infra.git

cd dev-vault-infra
cp .env.example .env      # set DOMAIN, CERTBOT_EMAIL, POSTGRES_PASSWORD

# 1) issue the first TLS certificate (run once).
#    Tip: STAGING=1 ./init-letsencrypt.sh first, to avoid rate limits while testing.
chmod +x init-letsencrypt.sh
./init-letsencrypt.sh

# 2) bring up the full stack
docker compose -f compose.prod.yml up -d --build
```

### How TLS works here

- **First issuance** — nginx can't start without a certificate, and a certificate
  can't be issued without nginx answering the ACME challenge.
  `init-letsencrypt.sh` breaks the cycle: it drops a dummy self-signed cert, starts
  nginx, then swaps in a real Let's Encrypt cert via the http-01 webroot challenge.
- **Challenge path** — nginx serves `/.well-known/acme-challenge/` from a shared
  volume that certbot writes into.
- **Renewal** — the `certbot` service runs `certbot renew` twice a day; the `nginx`
  service reloads every 6h so a renewed certificate is picked up with no downtime.
  (Containers can't signal each other directly, hence the two loops.)

## Environment variables

Defined in `.env` (see `.env.example` for the template):

| Variable            | Description                                                | Example           |
| ------------------- | ---------------------------------------------------------- | ----------------- |
| `DOMAIN`            | Base domain; subdomains `api`/`app`/`admin` derive from it | `YOUR_DOMAIN`     |
| `CERTBOT_EMAIL`     | Email for Let's Encrypt registration and expiry notices    | `you@example.com` |
| `POSTGRES_PASSWORD` | Password for the private PostgreSQL instance               | —                 |

### Where config lives

- **API URL** of each frontend is baked into its bundle at build time via the
  `VITE_API_URL` build-arg (set in `compose.prod.yml`). Change the domain in one
  place — `.env` `DOMAIN` — and rebuild.
- **CORS allowlist** of the backend is passed as `CORS_ORIGIN` (derived from
  `DOMAIN`) so it only trusts the real frontend origins.
- **Reverse proxy** config is templated: `${DOMAIN}` is substituted at container
  startup; nginx's own `$variables` are preserved via `NGINX_ENVSUBST_FILTER`.

## Next maturity steps

- Push images to a registry (GHCR) and pull instead of building on the host.
- Add CI to build and publish images per repo on merge to `main`.
- Move Postgres to a managed database or add automated backups.

## License

Private project — not for distribution.
