# dev-vault-infra

Production orchestration for **dev-vault**: three independently developed apps
served on their own subdomains behind a single Caddy reverse proxy.

## The dev-vault project

**dev-vault** is split into four repositories, developed and deployed independently:

| Repository                                                       | Role                                       | Local dev               |
| ---------------------------------------------------------------- | ------------------------------------------ | ----------------------- |
| [dev-vault-server](https://github.com/GrafSoul/dev-vault-server) | Backend API (NestJS)                       | `http://localhost:3030` |
| [dev-vault-client](https://github.com/GrafSoul/dev-vault-client) | Client SPA (React + Vite)                  | `http://localhost:3000` |
| [dev-vault-admin](https://github.com/GrafSoul/dev-vault-admin)   | Admin SPA (React + Vite)                   | `http://localhost:3001` |
| [dev-vault-infra](https://github.com/GrafSoul/dev-vault-infra)   | Production orchestration (Compose + Caddy) | —                       |

## Architecture

```text
Browser ──HTTPS──▶ Caddy (443, auto-TLS)
                     api.YOUR_DOMAIN    → backend  (NestJS, :3030)
                     app.YOUR_DOMAIN    → client   (static via nginx, :80)
                     admin.YOUR_DOMAIN  → admin    (static via nginx, :80)

backend ──private──▶ postgres (:5432) · redis (:6379)   # not exposed to the internet
```

Only Caddy publishes ports (80/443). Postgres and Redis have no public ports and
are reachable only over the private Docker network.

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

`compose.dev.yml` just includes each app's own `docker-compose.yml` (dev stage,
hot-reload, direct ports). The frontends read `VITE_API_URL=http://localhost:3030`
from their local `.env`.

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
cp .env.example .env      # set DOMAIN and POSTGRES_PASSWORD

docker compose -f compose.prod.yml up -d --build
```

Caddy fetches TLS certificates from Let's Encrypt automatically once the
subdomains resolve to the host.

## Environment variables

Defined in `.env` (see `.env.example` for the template):

| Variable            | Description                                                | Example       |
| ------------------- | ---------------------------------------------------------- | ------------- |
| `DOMAIN`            | Base domain; subdomains `api`/`app`/`admin` derive from it | `YOUR_DOMAIN` |
| `POSTGRES_PASSWORD` | Password for the private PostgreSQL instance               | —             |

### Where config lives

- **API URL** of each frontend is baked into its bundle at build time via the
  `VITE_API_URL` build-arg (set in `compose.prod.yml`). Change the domain in one
  place — `.env` `DOMAIN` — and rebuild.
- **CORS allowlist** of the backend is passed as `CORS_ORIGIN` (derived from
  `DOMAIN`) so it only trusts the real frontend origins.

## Next maturity steps

- Push images to a registry (GHCR) and pull instead of building on the host.
- Add CI to build and publish images per repo on merge to `main`.
- Move Postgres to a managed database or add automated backups.

## License

Private project — not for distribution.
