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
| `FIREBASE_AUTH_STUB` | Accept `Bearer test:<uid>:<email>` stub tokens instead of verifying real Firebase ID tokens |
| `STRIPE_SECRET_KEY` | Stripe secret key (test mode locally/staging) |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret (`whsec_…`) |
| `STRIPE_PERSONAL_PACK_PRICE_ID` | Stripe Price ID for the 3-credit / $20 personal pack |
| `STRIPE_CHECKOUT_SUCCESS_URL` | Browser return URL after successful Checkout (include `{CHECKOUT_SESSION_ID}`) |
| `STRIPE_CHECKOUT_CANCEL_URL` | Browser return URL when Checkout is cancelled |
| `OPENROUTER_API_KEY` | OpenRouter API key for AI draft generation |
| `OPENROUTER_BASE_URL` | OpenRouter API base (default `https://openrouter.ai/api/v1`) |
| `AI_KILL_SWITCH` | When `true`, reject new nonessential AI work without calling the provider |
| `AI_BUDGET_STOP` | When `true`, same stop behavior for budget exhaustion |
| `EMAIL_INLINE_JOBS` | When `true`, run non-coalesced notification mail in-process (default for local Compose) |
| `MAIL_ADAPTER` | `log` (default) or `mailgun` |
| `MAILGUN_API_KEY` / `MAILGUN_DOMAIN` / `MAILGUN_FROM` | Mailgun HTTP credentials when `MAIL_ADAPTER=mailgun` |
| `APP_ORIGIN` | Frontend origin used in email CTA links |
| `STAFF_INBOX` | Staff-only copy destination (default `hello@careerstack.co`) |

No credentials are committed. `.env` is gitignored; use `.env.example` placeholders only.

## Stripe (personal pack)

Personal credit packs use Stripe Checkout (no card fields in CareerStack). Register the webhook endpoint in the Stripe Dashboard (test mode for staging):

`POST https://<api-host>/api/v1/stripe/webhooks`

Events to enable: `checkout.session.completed`, `checkout.session.expired`, `checkout.session.async_payment_failed`.

Local forwarding:

```bash
stripe listen --forward-to localhost:3000/api/v1/stripe/webhooks
# set STRIPE_WEBHOOK_SECRET to the CLI-printed whsec_…
```

On successful Checkout, the API grants +3 personal credits idempotently (deduped by Stripe event ID). Cancelled or abandoned Checkout leaves the balance unchanged.

`Billing::ReconcilePurchasesJob` is registered in [`config/recurring.yml`](config/recurring.yml) to flag completed purchases missing ledger lots/grants, and stale pending sessions.

## OpenRouter (AI project generation)

Project draft generation uses OpenRouter behind a provider-neutral adapter.

1. Create an OpenRouter API key and set `OPENROUTER_API_KEY` in `.env` (and Compose / Secret Manager for staging).
2. Optional: `OPENROUTER_BASE_URL` (defaults to `https://openrouter.ai/api/v1`).
3. Runtime stops (no provider calls): `AI_KILL_SWITCH=true` or `AI_BUDGET_STOP=true`.
4. Local Compose defaults `AI_INLINE_JOBS=true` so generation runs in-process without a separate Solid Queue worker. Staging/production should run jobs via Solid Queue and leave `AI_INLINE_JOBS` unset/false.
5. Model + prompt versions live in `config/ai/registry.yml`.

Generate does **not** consume project credits; confirm still does.

## Identity API

Identity, onboarding, and workspace endpoints live under `/api/v1/*`. Every path except `/health`, `/ready`, `/up`, `/api/v1/stripe/webhooks`, and `/api/v1/public/*` requires `Authorization: Bearer <Firebase ID token>`; the first verified token for an email creates a CareerStack account in `pending_onboarding`. The Stripe webhook is public for Firebase auth but still requires a valid `Stripe-Signature`. Public project and profile GETs enforce server-side eligibility and return **404** (never 403) when ineligible. See [`openapi/openapi.yaml`](openapi/openapi.yaml) for the full contract.

`FIREBASE_AUTH_STUB` defaults to on in test, and in development until `FIREBASE_PROJECT_ID` is set. It is ignored in production, where real Firebase ID tokens are always verified against Google's JWKS. With the stub enabled:

```bash
curl -s http://localhost:3000/api/v1/session \
  -H "Authorization: Bearer test:local-uid-1:you@example.com"
```

Controlled taxonomies (roles, experience levels, organization structures and goals) are database-backed with stable term IDs. Seed or re-seed them idempotently with `bin/rails db:seed`.

Date of birth is collected only on the organization-invited onboarding path. It is never returned by any endpoint, is filtered from request logs, and only the derived `age_status` (`adult` | `minor` | `unknown`) is exposed. Transactional email and Mixpanel also omit date of birth and other users' emails.

The header **bell is the notification center**, not Inbox. Inbox remains the operational queue for applications, reviews, and escalations. Firebase Auth still owns magic-link sign-in email; Rails sends the rest through `TransactionalMail` (`MAIL_ADAPTER=log` locally, `mailgun` when configured).

## Background jobs

Solid Queue is installed with a separate queue database connection and schema. **No worker process is deployed yet** — local Compose and Cloud Run currently rely on inline escapes (`AI_INLINE_JOBS`, `REPORTS_INLINE_JOBS`, `EMAIL_INLINE_JOBS`). Staging's durable path is a Solid Queue worker including the `mailers` queue. Locally you can run `bin/jobs` when needed.

`Notifications::DigestJob` is registered hourly in production on `mailers`. It produces due-task, pending-invitation, and weekly activity rows, then delivers digest-tier mail only between 08:00 and 20:00 in the recipient's IANA timezone (`users.timezone`). Empty digests are never sent. Run on demand with `bin/rails runner Notifications::DigestJob.perform_now`. Until a worker is deployed, set `EMAIL_INLINE_JOBS=true` so non-coalesced mail runs in-process (coalesced events stay scheduled for 10 minutes and need an explicit deliver or a worker).

`OrganizationOffboardingSweepJob` is registered daily in production (05:00). It disables organizations whose offboarding window has ended and clears that org as the active workspace. Run on demand with `bin/rails runner OrganizationOffboardingSweepJob.perform_now`.

`AgeUpDetectionJob` is registered in [`config/recurring.yml`](config/recurring.yml) to run daily in production. It promotes organization-invited minors who have reached 18 in their organization's timezone, grants the Personal workspace and personal trial credit that were withheld, and flags them for visibility review so their profile stays private until they explicitly confirm. Run it on demand with `bin/rails runner AgeUpDetectionJob.perform_now`.

`InboxOverdueEscalationJob` is registered hourly in production. It marks overdue applications and team task reviews (>72h), creates creator reminder alerts, and opens durable escalations (Personal → staff target plus staff-only email; Organization → org managers/admins with Inbox alerts and in-app notifications). Run on demand with `bin/rails runner InboxOverdueEscalationJob.perform_now`.

`ProjectLifecycleSweepJob` is registered hourly in production. It evaluates active projects with an `ends_on` date: derived phases use UTC calendar boundaries (`ending_soon` within 7 days of end, `grace_period` for 7 days after end, then `expired`). Confirm requires `ends_on`. Expiration marks unresolved tasks `incomplete` and does not restore credits; all tasks assigned and approved auto-complete the project. Lifecycle Inbox alerts use kind `lifecycle`. Run on demand with `bin/rails runner ProjectLifecycleSweepJob.perform_now`.

## AI (OpenRouter)

Set `OPENROUTER_API_KEY` for project draft generation and solo task review. Runtime controls:

- `AI_KILL_SWITCH` / `AI_BUDGET_STOP` — reject new generation and review work without provider calls
- `AI_INLINE_JOBS=true` — run AI jobs in-process (default for local Compose without a worker)

Evidence files use Active Storage (Disk locally under `storage/`; configure private GCS for staging/production in `config/storage.yml`).

## Team joining

Team projects support `application`, `instant`, and `invite_only` joining modes (capacity 1–5; creator excluded). Membership join paths consume one workspace credit via the ledger. Key routes:

- `POST /api/v1/projects/:id/convert_to_team`, `POST .../join`, `POST .../leave`, `POST .../remove_member`
- `POST /api/v1/projects/:project_id/applications` (+ approve/reject)
- `POST /api/v1/projects/:project_id/invitations` and `POST /api/v1/project_invitations/:id/accept|decline`
- `PATCH /api/v1/tasks/:task_id/assignment`

Creator team task review and Inbox Approvals are live. Project completion, grace, and expiration close the timebox after the preferred end date.

## Profiles

Authenticated adults have a system-generated kebab-case profile slug (user-immutable). Own Profile is at `/profile` (Details · Activity · Skills & artifacts · Settings). Other eligible adults are readable at `GET /api/v1/profiles/:slug` and `/profile/:slug` when visibility is `public_adult`; restricted identities return 404 (not 403). Contribution stats and equal-weight activity events are derived, not editable. Age-up confirm/reverse uses `POST /api/v1/profiles/me/visibility` (and the existing `PATCH /api/v1/age_visibility`).

## Public surfaces

Unauthenticated visitors can open eligible public projects and public adult profiles outside the application shell:

- `GET /api/v1/public/projects/:slug` — redacted project DTO (no evidence, roster, submissions, credits, or messages)
- `GET /api/v1/public/profiles/:slug` — public adult profile DTO (same visibility rules as authenticated by-slug)
- Frontend routes: `/projects/:slug` and `/profile/:slug` (shell-less for anonymous; onboarded users enter the shell)

Projects have a stable kebab `slug` and `visibility` (`public` | `private`). Personal defaults to public; organization defaults to private. Anonymous `/api/v1/public/*` traffic is rate-limited via Rack::Attack.

## Organization administration

Staff (organization `admin` and `manager`) in an active Organization workspace can manage programs, members, and pooled credits. Participants never enter this surface.

Key routes (all require the `organization_id` to match the actor's **active** org workspace plus staff membership):

- `GET /api/v1/organizations/:organization_id/admin` — operational pulse, capabilities, upgrade-request summary, `workspace_status`
- `GET/POST /api/v1/organizations/:organization_id/programs`; `PATCH/DELETE /api/v1/programs/:id`; `POST .../archive`
- `GET /api/v1/organizations/:organization_id/memberships`; `PATCH /api/v1/organization_memberships/:id`; `POST .../remove`
- `GET /api/v1/organizations/:organization_id/invitations` (create remains `POST /api/v1/invitations`, always free)
- `GET/PUT /api/v1/organizations/:organization_id/upgrade_request` — one open request per org; logs a staff-notification intent to `hello@careerstack.co` and **does not send Mailgun**
- `POST /api/v1/workspaces/program_filter` — persist All programs vs a specific program for the actor's membership

Organization projects require `program_id` (active program only). Personal projects stay without a program. `GET /api/v1/credits/history` in an org workspace is administrator-only; managers can still read the balance.

## Organization reporting

Staff (admin and manager) in an Organization workspace can create immutable report snapshots:

- `GET/POST /api/v1/organizations/:organization_id/reports`
- `GET /api/v1/organization_reports/:id` (poll while `generating`)
- `POST /api/v1/organization_reports/:id/generate` — Solid Queue `reports` (or inline when `REPORTS_INLINE_JOBS=true` / test)
- `POST /api/v1/organization_reports/:id/download` — 15-minute signed URL; named reports that include minor names require `confirm_minor_names=true`
- `GET /api/v1/organizations/:organization_id/outcome_aggregates`

PDF/CSV generation does not consume credits. Date of birth is never included in files, JSON, logs, or Mixpanel. Aggregate-only exports strip names, emails, user ids, and free-text notes.

During offboarding read-only, exports still work. Disabled workspaces reject create/generate/download.

Participants record private outcomes via `GET/POST /api/v1/outcomes` while an Organization workspace is active. Outcomes are labeled self-reported and are omitted from profile DTOs.

If an existing org had no programs, backfill created an `active` program named `General` and attached existing org projects. Rename or archive it later if unused.

Offboarding is operator-only: `Organizations::StartOffboarding` (no product UI). Status moves `active` → `offboarding_readonly` (30 days) → `disabled`. `OrganizationOffboardingSweepJob` runs daily in [`config/recurring.yml`](config/recurring.yml). Disabled orgs are omitted from usable workspaces. Run the sweep on demand with `bin/rails runner OrganizationOffboardingSweepJob.perform_now`.


**Staging note:** Cloud Run may still require an authenticated invoker at the edge (org policy). Rails public allowlist is verified locally; unlock browser anonymous → API calls via the public invoker checklist in [`infra/README.md`](infra/README.md).

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

Specs run against the test database configured in `config/database.yml`, which defaults to the Compose Postgres on host port 55432. To run against a Postgres already listening on 5432 instead, override the connection for the command:

```bash
DATABASE_PORT=5432 DATABASE_USERNAME="$(whoami)" DATABASE_PASSWORD="" bundle exec rspec
```

Specs need no Firebase credentials: `spec/support/auth_helpers.rb` mints stub tokens, and `spec/support/identity_fixtures.rb` provides inline record builders (this project intentionally does not use FactoryBot).

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

Note: unauthenticated staging calls receive Cloud Run **403** before Rails because public invoker is org-policy blocked. Rails **401** envelope is verified locally. To unlock Netlify → API browser calls, follow the public invoker checklist in [`infra/README.md`](infra/README.md).
