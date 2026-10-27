# Handover

I wrote this for whoever sets the project up after me. The README explains why things are built the way they are. This file covers the steps.

You should have two things:
- **This repository:** Terraform in `infra/`, the GitHub Actions pipeline, scripts, tests and runbooks.
- **Three OutSystems application packages (.oap):**
  - `HDB Resale`: contains `HDBResale_Core` and `HDBResale_Admin`.
  - `Singapore HDB Insight`: contains `SingaporeHDBInsight`.
  - `HDB Resale Tests`: contains `HDBResale_Tests`. Only install this in Dev and Test.

There are two ways to set it up:
- **Option A, about an hour:** just run the app on an OutSystems environment you already have.
- **Option B, a day or more:** build the full setup on AWS, then install OutSystems and deploy through the pipeline.

## Option A: run the app on an existing environment

1. Publish the packages in this order: `HDB Resale`, then `Singapore HDB Insight`, then `HDB Resale Tests`.
   - Use Service Studio (Environment > Open Files) or Service Center (Factory > Solutions).
   - If a module complains about outdated references, open it, choose Manage Dependencies > Refresh All, and publish again.
2. In the Users app, give yourself the `HDBAdmin` role.
3. Open `https://<env>/HDBResale_Admin/SyncAdmin` and click *Run sync now*.
4. After about 12 minutes, click *Refresh*. The run should show `Succeeded` and health should show `OK`.
5. Open `https://<env>/SingaporeHDBInsight/` and try TAMPINES with 4 ROOM.

To run the automated tests too:
1. Apply the Test settings from step 4 of Option B.
2. Run:

   ```bash
   TESTS_BASE_URL=https://<env>/HDBResale_Tests TEST_API_TOKEN=<token> ./scripts/run-tests.sh all junit.xml
   ```

Once Core points at the mock, that environment's nightly sync uses the mock as well.

## Option B: the full setup

You'll need:
- an AWS account and the AWS CLI
- Terraform 1.6 or later
- an OutSystems 11 self-managed licence and LifeTime
- a GitHub repository
- a domain with an ACM certificate in `ap-southeast-1`

### 1. Terraform

1. Create an S3 bucket (versioned, encrypted, not public) and a DynamoDB table with a `LockID` key. These hold the Terraform state.
2. Copy both `infra/envs/*.backend.hcl.example` files to `.backend.hcl` and fill in the bucket and table names. Git ignores the copies.
3. In `infra/envs/test.tfvars` and `prod.tfvars`, replace every `REPLACE-ME`:
   - `app_hostname`
   - `certificate_arn`
   - `admin_allowed_cidrs`: your office or VPN ranges. An empty list blocks the admin app from the internet completely.
   - `alert_emails`
4. Apply Test first, then Prod:

```bash
cd infra
terraform init -backend-config=envs/test.backend.hcl
terraform plan -var-file=envs/test.tfvars -out=test.plan
terraform apply test.plan

terraform init -reconfigure -backend-config=envs/prod.backend.hcl
terraform plan -var-file=envs/prod.tfvars -out=prod.plan
terraform apply prod.plan
```

After each apply:
1. Point your DNS name at the `alb_dns_name` output.
2. Confirm the SNS email subscriptions.
3. Note down the `db_endpoint` and `db_master_secret_arn` outputs. You'll need them for the OutSystems install.

### 2. Install OutSystems (manual)

Terraform only builds the servers. Connect to them with SSM Session Manager; there's no SSH or RDP access.

1. On the deployment controller:
   1. Install Platform Server.
   2. Run Configuration Tool against `db_endpoint`. Get the admin password from `db_master_secret_arn` with `aws secretsmanager get-secret-value`.
   3. Create a separate runtime login that can only read and write data.
   4. Add the licence.
   5. Install Service Center and OutSystems UI.
2. On each front-end server, install Platform Server and register it with the controller.
3. In LifeTime:
   1. Add the Test and Prod environments.
   2. Set up the Development, Test, Production pipeline.
   3. Create a service account that can only tag and deploy, and keep its token.

OutSystems' own installation guides cover the exact screens.

### 3. GitHub

1. Push the repository.
2. Create two environments:
   - `test`
   - `production`, with required reviewers. Those reviewers are the approval step.
3. Add these repository variables:
   - **`LT_URL`:** the LifeTime address.
   - **`LT_ENV_DEV`, `LT_ENV_TEST`, `LT_ENV_PROD`:** the environment names exactly as LifeTime shows them.
   - **`LT_APPS_PROD`:** `HDB Resale,Singapore HDB Insight`.
   - **`LT_APPS_TEST_ONLY`:** `HDB Resale Tests`.
   - **`TEST_HOST` and `PROD_HOST`:** the Test and Prod host names.
   - **`AI_MENTOR_URL`:** a link to AI Mentor Studio.
4. Add two secrets:
   - **`LT_TOKEN`:** the service-account token.
   - **`TEST_API_TOKEN`:** any long random value. Use the same value for `TestApiToken` in the next section.
5. Open a small pull request and check that `ci.yml` passes.

### 4. Deploy and configure

1. Publish the three packages to Development (as in Option A).
2. Run the Release workflow in GitHub with a version such as `1.0.0`. The first run will stop at the tests until the next step is done.
3. Set these site properties in Service Center:

   | Setting | Dev | Test | Prod |
   |---|---|---|---|
   | Core `DataGovSG_ApiKey` | optional | optional | from Secrets Manager |
   | Core `TestSupportEnabled` | True | True | False |
   | Core `SearchApiEnabled` | False | True only while load testing | False |
   | Core `SyncPageSize` / `SyncPageDelaySeconds` / `SyncRetryBaseSeconds` | default | 10 / 0 / 1 | default |
   | Core DataGovSG Effective URL | default | `https://<test-host>/HDBResale_Tests/rest/DataGovMock` | default |
   | Tests `TestsEnabled` / `TestApiToken` | True / token | True / token | not installed |

4. Give the operators the `HDBAdmin` role.
5. Run the release again. This time it runs all the tests, waits for approval, deploys to Prod, checks health, and rolls back by itself if health isn't OK.
6. From an allowed network, open SyncAdmin in Prod and run the first sync.

### 5. Final checks

- `CORE_BASE_URL=https://<prod-host>/HDBResale_Core ./scripts/check-health.sh` prints `OK`.
- The `hdb-resale-prod-health-not-ok` alarm is OK, and the canary is passing.
- SyncAdmin returns 403 from outside the allowed IP ranges.
- The `HDB Resale Tests` app isn't in Prod.
- A k6 run against Test has been recorded.
- A restore drill has been done in Test (see `docs/runbooks/dr-restore.md`).

## After go-live

Use the runbooks in `docs/runbooks/` for releases, failed syncs, restores and secret rotation. If bad data was loaded, *Roll back to previous snapshot* in SyncAdmin fixes it in seconds.

## Things I haven't been able to test yet

Section 8 of the README has the full list. The main ones:
- the 51 platform tests haven't run
- `terraform plan` hasn't run against a real account
- the LifeTime API calls haven't been tried against a real LifeTime
- the *Run sync now* and *Roll back* buttons haven't been clicked from SyncAdmin yet (the nightly timer runs have all succeeded)

Please expect a few fixes on the first run.
