# CareerStack infrastructure (OpenTofu)

OpenTofu roots live under `envs/staging` and `envs/production`. Staging auto-deploys from `main`. Production infrastructure is applied from the operator laptop; the application image is released only by the `workflow_dispatch` production workflows.

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

## Cloud Run image and port (CI-managed)

Staging Cloud Run is bootstrapped with the public `hello` image on port `8080`. After the first GitHub Actions staging deploy, the live service uses the Artifact Registry API image on port `3000`.

OpenTofu intentionally ignores subsequent drift on:

- `template[0].containers[0].image`
- `template[0].containers[0].ports`

so a later `tofu apply` does not replace the CI-deployed API with `hello` / `8080`. To change image or port, use the staging deploy workflow (or `gcloud run services update`), not OpenTofu.

## Production apply (operator laptop)

`careerstack-prod` (project number `732555935345`) is the production GCP project. OpenTofu creates Cloud Run, Cloud SQL, Artifact Registry, the private bucket, Secret Manager, and Workload Identity inside that project. Do not create those resources by hand in the Cloud Run console.

There is no long-lived `staging` git branch. Merges to `main` deploy staging. Production app releases stay on **Actions → Deploy production → Run workflow**, which waits for the GitHub Environment `production` reviewer.

### One-time console prerequisites

1. **State bucket** (same pattern as staging; OpenTofu cannot create the bucket that holds its own state):
   ```bash
   gcloud config set project careerstack-prod
   gcloud storage buckets create gs://careerstack-tfstate-prod \
     --location=us-east5 \
     --uniform-bucket-level-access \
     --public-access-prevention
   ```
2. **APIs** used by the module:
   ```bash
   gcloud services enable \
     run.googleapis.com \
     sqladmin.googleapis.com \
     artifactregistry.googleapis.com \
     secretmanager.googleapis.com \
     iam.googleapis.com \
     cloudresourcemanager.googleapis.com \
     serviceusage.googleapis.com \
     monitoring.googleapis.com \
     billingbudgets.googleapis.com \
     storage.googleapis.com \
     iamcredentials.googleapis.com
   ```
3. **Org policy exception** so browsers can call Cloud Run with Firebase tokens. Repeat the staging checklist below for project `careerstack-prod`. Until it exists, leave `allow_unauthenticated_invoker = false`. After the exception propagates, set it to `true` in `envs/production/terraform.tfvars` and apply again.
4. **Firebase.** Create a production Firebase project. Do not reuse `careerstack-staging`. The default OpenTofu value is `firebase_project_id = "careerstack-prod"` (Firebase added to this GCP project). Authorized domains: `app.careerstack.co` and the production Netlify hostname. Put the web config on the frontend GitHub Environment `production`, and `FIREBASE_PROJECT_ID` on the backend environment.
5. **Netlify production site.** Create a new site with manual deploys and no Git connection. Do not attach `app.careerstack.co` to `careerstack-frontend-v2.netlify.app` — that site is staging, and every `main` merge publishes it. Add custom domain `app.careerstack.co` on the new site and the DNS record Netlify shows. `admin.careerstack.co` stays a separate site.
6. **GitHub Environment `production`** (both repos already require reviewer `haniaroad`). After `tofu output`:
   - Backend variables: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_DEPLOY_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID`, `GCS_PROJECT_ID`, `GCS_BUCKET`, `GCS_SERVICE_ACCOUNT_EMAIL`
   - Backend secrets, when live checkout, mail, and AI should work: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PERSONAL_PACK_PRICE_ID`, `MAILGUN_API_KEY`, optional `MAILGUN_DOMAIN` / `MAILGUN_FROM` (default `careerstack.co` / `hello@careerstack.co`), `OPENROUTER_API_KEY`
   - Frontend: the Netlify token stays on the staging environment (`NETLIFY_AUTH_TOKEN`). Repository variables `PRODUCTION_NETLIFY_SITE_ID`, `PRODUCTION_VITE_API_BASE_URL` (Cloud Run URL), `PRODUCTION_VITE_FIREBASE_API_KEY`, `PRODUCTION_VITE_FIREBASE_AUTH_DOMAIN`, `PRODUCTION_VITE_FIREBASE_PROJECT_ID`, `PRODUCTION_VITE_FIREBASE_APP_ID`, optional `PRODUCTION_SITE_URL`, `PRODUCTION_VITE_MIXPANEL_TOKEN`, `PRODUCTION_VITE_SENTRY_DSN`. **Deploy production** approves on the `production` environment, then publishes with those variables.
7. **Stripe live webhook** (when live keys are in use): `POST https://<prod-cloud-run-host>/api/v1/stripe/webhooks`.

A later `tofu apply` resets Cloud Run env vars to the OpenTofu set and drops workflow-managed secrets (Stripe, Mailgun, OpenRouter). Re-run **Deploy production** after an apply that touches the service.

### Apply

```bash
cd infra/envs/production
tofu init
tofu plan
tofu apply
tofu output
```

Cloud SQL has deletion protection and daily backups. The private bucket does not force-destroy. The service boots the public `hello` image until the first production workflow deploy, which replaces the image and port `3000`. `bin/docker-entrypoint` runs `db:prepare` on boot. No Solid Queue worker service is deployed; inline job flags stay on.

## What this change does not do

- No deployed Solid Queue worker service
- No `admin.careerstack.co` Netlify site in this cutover

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

### Expected after fix

- `GET /health` → `{"status":"ok"}` (no Google 403 HTML)
- Unauthenticated `GET /api/v1/session` → Rails **401 JSON** with `Access-Control-Allow-Origin` for Netlify (not Cloud Run 403)
- Google / magic-link → `GET /api/v1/session` **200** → new users land on `/onboarding` (“Complete your profile”), not `/sign-in` (“Create your account”)

Magic-link email delivery is configured in the Firebase Console (not Cloud Run). See the frontend README magic-link troubleshooting section.

Security note: public invoker only opens the Cloud Run door. Rails still requires a valid Firebase ID token on `/api/v1/*` (except health/ready). Keep CORS limited to known frontend origins.
