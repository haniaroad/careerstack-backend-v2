# CareerStack Backend V2

Rails API-only foundation for CareerStack. This repository owns the API, Solid Queue configuration, OpenAPI skeleton, Docker/Compose for local API+Postgres, and OpenTofu for GCP staging under `infra/`.

## Clone path caveat

Some checkouts nest as `Documents/careerstack-backend-v2/careerstack-backend-v2`. Always run commands from the directory that contains `Gemfile` and `openspec/config.yaml`.

## Prerequisites

- Docker + Colima (or Docker Desktop): `colima start`
- Ruby matching `.ruby-version` (for non-Compose local runs)
- OpenTofu (`tofu`) for infrastructure
- Google Cloud SDK with Application Default Credentials for operators: `gcloud auth application-default login`

## Local with Compose

```bash
cp .env.example .env   # optional for host-side rails
docker compose up --build
curl -s http://localhost:3000/health
curl -s http://localhost:3000/ready
```

Postgres is published on host port **55432** (container 5432) so it does not collide with a local Postgres on 5432/5433. From the host, set `DATABASE_PORT=55432`.

Compose starts `api` + `postgres`. The `web` service name is reserved for the frontend Compose stack.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` / `DATABASE_*` | Primary Postgres |
| `QUEUE_DATABASE_URL` / `QUEUE_DATABASE_NAME` | Solid Queue database (same instance, separate DB) |
| `CORS_ORIGINS` | Comma-separated browser origins |
| `SECRET_KEY_BASE` | Rails secret (required in production) |
| `SENTRY_DSN` | Optional error reporting |
| `SENTRY_ENVIRONMENT` | Sentry environment label |
| `FIREBASE_PROJECT_ID` | Staging Firebase project ID (required when `FIREBASE_AUTH_STUB` is false) |
| `FIREBASE_AUTH_STUB` | When `true` (default in development/test), accept `Bearer test:<uid>:<email>` tokens |

Identity APIs live under `/api/v1/*` and require a verified Firebase ID token (or stub token locally). Seed taxonomies with `bin/rails db:seed`.

No credentials are committed. `.env` is gitignored; use `.env.example` placeholders only.

## Background jobs

Solid Queue is installed with a separate queue database connection and schema. **No worker process is deployed yet** — that lands with the first background job change. Locally you can run `bin/jobs` when needed.

## Tests and quality

```bash
bundle install
bin/rails db:prepare
bundle exec rspec
bin/rubocop
bin/brakeman --no-pager
bundle exec bundler-audit check --update
bin/rails openapi:validate
```

## Infrastructure

See [`infra/README.md`](infra/README.md) for OpenTofu staging apply steps (operator ADC) and console-only setup notes.

Staging Cloud Run (after apply): `https://careerstack-api-njq2cbb5vq-ul.a.run.app`

WIF provider and deploy SA outputs come from `cd infra/envs/staging && tofu output`.

## Verification checklist (foundation)

- [x] Local Compose: `GET /health` and `GET /ready` succeed
- [x] Local Compose: unauthenticated non-allowlisted path returns 401 envelope
- [x] Staging API: Rails image deployed; `/health` and `/ready` succeed (authenticated invoker; org policy blocks `allUsers`)
- [x] Staging frontend Netlify site loads (`https://careerstack-frontend-v2.netlify.app`)
- [x] CORS allowlist includes the Netlify staging origin
- [x] Staging deploy workflow smoke-checks `/health` via WIF identity token

Note: unauthenticated staging calls receive Cloud Run **403** before Rails because public invoker is org-policy blocked. Rails **401** envelope is verified locally.
