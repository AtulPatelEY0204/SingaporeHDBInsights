# Secrets and rotation

Secret values never go in Git, Terraform state or the OutSystems modules. They're kept in AWS Secrets Manager, with one KMS key per stack, and copied into OutSystems Secret site properties, which Service Center masks.

| Secret | Where it's stored | Used by | Rotate |
|---|---|---|---|
| RDS master password | RDS-managed secret (`db_master_secret_arn` output) | Configuration Tool, admin login | Automatically by AWS |
| OutSystems runtime DB login | Secrets Manager | Configuration Tool, runtime login (DML only) | Every 90 days |
| data.gov.sg API key | `hdb-resale-<env>/datagov-api-key` | `HDBResale_Core`, `DataGovSG_ApiKey` | Every 90 days, or immediately if exposed |
| Test runner token | `hdb-resale-test/test-api-token` (not in Prod) | `HDBResale_Tests` `TestApiToken`, and the GitHub secret `TEST_API_TOKEN` | Every 90 days |
| LifeTime service account token | GitHub secret `LT_TOKEN` | `scripts/lifetime.py` | Every 90 days; give it deploy rights only |

## Rotating the data.gov.sg API key

1. Generate a new key on the data.gov.sg developer portal. Leave the old one active for now.
2. Store the new key:

   ```bash
   aws secretsmanager put-secret-value --secret-id hdb-resale-prod/datagov-api-key --secret-string '<new key>'
   ```

3. Paste it into `DataGovSG_ApiKey`. You'll find it in Service Center under Factory > Modules > HDBResale_Core > Site Properties. It takes effect without a publish.
4. Make sure the next sync works (or click *Run sync now*), then revoke the old key.

## Rotating the test runner token

1. Generate a new value, for example with `openssl rand -hex 32`.
2. Save it in `hdb-resale-test/test-api-token`.
3. Set it in two places:
   - `TestApiToken` in `HDBResale_Tests`, through Service Center
   - the GitHub secret `TEST_API_TOKEN`
4. Run `run-tests.sh unit` to check that the new token works.

## If a secret leaks

1. Rotate it straight away.
2. Search CloudTrail and the load balancer logs for any use of the old value.
3. Record the incident.
