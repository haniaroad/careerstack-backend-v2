# CareerStack infrastructure (OpenTofu)

OpenTofu root for GCP staging lives under `envs/staging`. Production modules are intentionally **not applied** in the `establish-platform-foundation` change.

## Prerequisites

- OpenTofu 1.x (`tofu`)
- `gcloud` authenticated with Application Default Credentials:
  ```bash
  gcloud auth application-default login
  gcloud config set project careerstack-staging
  ```
- Access to remote state bucket `gs://careerstack-tfstate-staging`
- Billing-linked project `careerstack-staging` (11197815680) in `us-east5`

## Staging apply (operator laptop)

```bash
cd infra/envs/staging
tofu init
tofu plan
tofu apply
```

Outputs include Cloud Run URL and Artifact Registry repository used by GitHub Actions.

## Console-only steps (not managed by OpenTofu)

1. **Netlify staging site** — create the site, note `NETLIFY_SITE_ID`, and store `NETLIFY_AUTH_TOKEN` + `NETLIFY_SITE_ID` in the GitHub Environment `staging` for `careerstack-frontend-v2`.
2. **GitHub Environments** — `staging` and `production` exist on both app repos. `production` requires reviewer `haniaroad`. Production deploy workflows are `workflow_dispatch`-only. Do not put production deploy triggers on laptop scripts.
3. **GitHub repository variables/secrets for backend deploy** — after `tofu apply`, copy WIF provider resource name, deploy service account email, Artifact Registry path, and Cloud Run service name into the `staging` environment (or repository variables referenced by workflows). Useful outputs:
   ```bash
   cd infra/envs/staging && tofu output
   ```
4. **Branch protection** — enabled on `main` for both public repos (backend checks: `lint`, `security`, `test`, `docker`; frontend: `quality`).

## What this change does not do

- No `tofu apply` against `careerstack-prod`
- No production Cloud Run / Cloud SQL / Netlify production cutover
- No deployed Solid Queue worker service

## Org policy note

`roles/run.invoker` for `allUsers` is blocked by organization policy on `careerstack-staging`. Grant unauthenticated access only after an approved exception; until then, health smoke checks from the public internet require an authenticated invoker or a temporary policy change.
