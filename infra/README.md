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

## Org policy note — public Cloud Run invoker (required for Netlify SPA)

The Netlify frontend calls Cloud Run with a **Firebase** `Authorization: Bearer` token.
Cloud Run's IAM gate expects a **Google** identity token unless the service allows
unauthenticated invocation. With `allUsers` blocked, browsers get **403** on OPTIONS
preflight (shown as CORS / "Failed to fetch") before Rails CORS or Firebase auth runs.

### Console checklist (operator)

1. **Confirm the failure** (should be Google Frontend 403, not Rails JSON):
   ```bash
   curl -sS -D - -o /dev/null \
     -X OPTIONS "https://careerstack-api-njq2cbb5vq-ul.a.run.app/api/v1/session" \
     -H "Origin: https://careerstack-frontend-v2.netlify.app" \
     -H "Access-Control-Request-Method: GET" \
     -H "Access-Control-Request-Headers: authorization"
   ```

2. **Org policy exception** (Organization Policy Admin on the parent org):
   - Open [Organization policies](https://console.cloud.google.com/iam-admin/orgpolicies) for the org that owns `careerstack-staging`.
   - Find **Domain restricted sharing** (`constraints/iam.allowedPolicyMemberDomains`) or any policy that rejects `allUsers` on Cloud Run.
   - Add a **project-level override** for `careerstack-staging` that allows public principals (`allUsers`) **or** exempt this project from that constraint for staging only.
   - Save and wait a few minutes for propagation.

3. **Grant public invoker** (after the exception applies):
   ```bash
   gcloud auth login
   gcloud config set project careerstack-staging

   gcloud run services add-iam-policy-binding careerstack-api \
     --region=us-east5 \
     --member=allUsers \
     --role=roles/run.invoker
   ```
   Or set in `infra/envs/staging/terraform.tfvars`:
   ```hcl
   allow_unauthenticated_invoker = true
   ```
   then `cd infra/envs/staging && tofu apply`.

4. **Ensure Firebase project ID is on the service** (Rails verifies real ID tokens in production):
   ```bash
   gcloud run services update careerstack-api \
     --region=us-east5 \
     --update-env-vars=FIREBASE_PROJECT_ID=careerstack-staging
   ```
   (Also managed by OpenTofu / staging deploy workflow going forward.)

5. **Verify**
   ```bash
   # Public health (no auth) should be Rails JSON 200
   curl -sS "https://careerstack-api-njq2cbb5vq-ul.a.run.app/health"

   # Preflight should include ACAO for Netlify (not 403 HTML)
   curl -sS -D - -o /dev/null \
     -X OPTIONS "https://careerstack-api-njq2cbb5vq-ul.a.run.app/api/v1/session" \
     -H "Origin: https://careerstack-frontend-v2.netlify.app" \
     -H "Access-Control-Request-Method: GET" \
     -H "Access-Control-Request-Headers: authorization"
   ```

6. Hard-refresh the Netlify app and retry Google / magic-link sign-in.

Security note: public invoker only opens the Cloud Run door. Rails still requires a valid Firebase ID token on `/api/v1/*` (except health/ready). Keep CORS limited to known frontend origins.
