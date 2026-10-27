# Database restore and region recovery

The targets are in README section 3:

| Failure | RPO | RTO |
|---|---|---|
| Corruption or operator error | 5 minutes or less | 1 hour or less |
| Losing the whole region | 24 hours or less | 8 hours or less |

Practise this in Test once a quarter, and record the result at the bottom of this file.

## A. Point-in-time restore (same region)

1. **Pick a restore time** just before the incident, in UTC, within the `db_backup_retention_days` window.

2. **Restore to a new instance:**

   ```bash
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier hdb-resale-prod \
     --target-db-instance-identifier hdb-resale-prod-restore-$(date +%Y%m%d%H%M) \
     --restore-time 2026-10-24T03:15:00Z \
     --db-subnet-group-name hdb-resale-prod \
     --vpc-security-group-ids <db security group id> \
     --multi-az --no-publicly-accessible
   ```

3. **Test the restored instance on one front-end server first.**
   1. Connect to the server with SSM.
   2. Point Configuration Tool at the new endpoint and restart the services.
   3. Run `check-health.sh` against that server.
   4. Check that SyncAdmin (`/HDBResale_Admin/SyncAdmin` on that server) shows the expected runs.

4. **Move the remaining servers over.**
   1. Point them at the new endpoint and restart them.
   2. Put them back behind the load balancer.
   3. Rename the instances, or update `identifier` in Terraform, so the old instance can be retired.

5. **Catch up any newer data.** Click *Run sync now* in SyncAdmin.

6. **Record the actual RPO and RTO.** The RPO is the incident time minus the restore time.

## B. Losing the region (ap-southeast-1)

1. **Rebuild the stack** in `ap-southeast-3`: run `terraform apply` with `region = "ap-southeast-3"` and a separate state key.
2. **Restore the database** from the latest recovery point in the `hdb-resale-prod-dr` vault (AWS Backup > Restore), into the new DB subnet group.
3. **Reinstall OutSystems:**
   1. Install Platform Server on the new servers.
   2. Run Configuration Tool against the restored database.
   3. Register the environment in LifeTime.
4. **Set the secrets and site properties again**, following `secret-rotation.md`.
5. **Switch traffic over:**
   1. Point DNS at the new load balancer.
   2. Run `check-health.sh`.
   3. Click *Run sync now*.

The new WAF uses the same `admin_allowed_cidrs`. If the admins connect from different IPs during a disaster, update the tfvars first, or SyncAdmin will return 403.

## Drill log

| Date | Type | Restore point | RPO achieved | RTO achieved | Notes |
|---|---|---|---|---|---|
| | | | | | |
