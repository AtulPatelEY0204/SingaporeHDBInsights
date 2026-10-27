# Release and rollback

Releases are run by `.github/workflows/release.yml`, which uses `scripts/lifetime.py` to talk to LifeTime.

## Environments

| Environment | Apps | Notes |
|---|---|---|
| Development | Core, Admin, UI, Tests | `TestSupportEnabled` and `TestsEnabled` are True |
| Test | Core, Admin, UI, Tests | Core's DataGovSG Effective URL points at `.../HDBResale_Tests/rest/DataGovMock`. `SyncPageSize` 10, `SyncPageDelaySeconds` 0, `SyncRetryBaseSeconds` 1. `SearchApiEnabled` only while load testing |
| Production | Core, Admin, UI | `TestSupportEnabled` and `SearchApiEnabled` are False. Real data.gov.sg URL. Admin path limited to `admin_allowed_cidrs` |

The *HDB Resale* app contains both Core and Admin.

## Normal release

1. Publish your changes in Development.
2. In GitHub, go to Actions > Release > Run workflow. Enter a version (for example `1.4.0`) and a short change note.
3. The workflow then does the following, and stops at the first failure:
   1. Runs the static checks.
   2. Tags the apps in Development.
   3. Deploys them to Test.
   4. Runs the unit, integration and end-to-end suites, one at a time.
   5. Runs the Playwright smoke tests.
4. It then waits for approval. Before you approve, check:
   - AI Mentor Studio has no new critical findings.
   - The test reports are green.
   - The production site properties haven't changed.
5. After approval it:
   1. Saves the current production versions as `prod-before.json`.
   2. Deploys Core, Admin and UI to production.
   3. Checks health for up to 5 minutes.

If the health check fails, the rollback job redeploys the saved versions and checks health again.

## Manual rollback

Use this if a problem shows up after the pipeline has finished.

1. Download the `prod-before` artifact from the release you want to undo.
2. Run:

   ```bash
   LT_URL=https://lifetime.example.com LT_TOKEN=*** python scripts/lifetime.py deploy-versions --source Test --target Production --versions-file prod-before.json --notes "Manual rollback"
   ```

3. Check health:

   ```bash
   CORE_BASE_URL=https://hdb.example.com/HDBResale_Core ./scripts/check-health.sh
   ```

Schema changes are always additive (I never drop columns or tables), so an older version runs fine on a newer schema.

## Bad data isn't a release problem

If a nightly load brought in wrong data, don't roll back the code. In SyncAdmin (`/HDBResale_Admin/SyncAdmin`), click *Roll back to previous snapshot*. It's instant and it's logged. See `sync-failure-triage.md`.

## LifeTime says `needs_user_intervention`

This usually means an outdated consumer or a conflict. Open the deployment plan in LifeTime, sort it out there, and rerun the failed job in GitHub.
