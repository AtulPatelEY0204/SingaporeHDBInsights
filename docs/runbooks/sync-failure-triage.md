# Sync failed or data is stale

You'll usually end up here because of one of these:
- the `hdb-resale-prod-health-not-ok` alarm (the health status hasn't been OK for 10 minutes)
- the amber badge on PriceCheck
- a `Failed` run in SyncAdmin (`https://<host>/HDBResale_Admin/SyncAdmin`)

SyncAdmin only works from the allowed IP ranges, with the `HDBAdmin` role.

Users aren't affected straight away. They keep seeing the last good snapshot; only the "data as of" date gets older.

## 1. Check the health status

```bash
CORE_BASE_URL=https://hdb.example.com/HDBResale_Core ./scripts/check-health.sh
```

- **`NoData`:** there's no active snapshot (a new environment, or AppState was lost). Go to step 4.
- **`Stale` and `LastSyncStatus=Failed`:** recent syncs have failed. Go to step 2.
- **`Stale` and `LastSyncStatus` is `Succeeded` or `Running`:** the timer isn't running or is stuck. Go to step 3.
- **An HTTP error or timeout:** the site or the database is down. Treat it as an infrastructure incident and check the load balancer, EC2 and RDS alarms.

## 2. A sync ran and failed

In SyncAdmin, look at the Details column under Recent sync runs.

- **`failed after N attempts`, `MockOutage` or `429`:** data.gov.sg is down or rate limiting. Wait for the next nightly run, or click *Run sync now* later. If it keeps happening, set `DataGovSG_ApiKey` or increase `SyncPageDelaySeconds`.
- **`unusable or empty page`:** the API sent an error, HTML, or fewer pages than it claimed. Look at the raw response in the Integrations log, then try again.
- **`[TRUNCATED]`:** fewer rows arrived than the source total. Usually temporary, so try again.
- **`[SHRUNK]`:** the new data is less than 99% of the current snapshot. Don't force it through. Check whether data.gov.sg reset the dataset or changed the resource id, and talk to the data owner before lowering `SyncMinRowRatio`.
- **`[REJECTS]`:** more than 0.1% of rows couldn't be parsed, which usually means the format changed.
  1. Look in `SyncRejectedRow` for that run; it has the raw JSON and the reason.
  2. Fix the parser in `Sync_LoadPage`.
  3. Add a test row to `Int_LoadPage_*`.
  4. Release.
- **`[MONTH]`:** the latest month went backwards. That's an upstream problem, so contact the data owner.

A failed run deletes its partial snapshot automatically, so users keep the previous data.

## 3. No run at all, or a run stuck in `Running`

1. In Service Center, go to Monitoring > Timers and check `SyncResaleData`:
   - Is it enabled?
   - When is the next run?
   - Did the last run error?
2. Check that the `SyncEnabled` site property is True.
3. A run killed by the 60-minute timer limit stays `Running`. This is a known gap.
   - Start *Run sync now*; a successful run clears the alarm.
   - The stuck row is harmless. Its snapshot is never activated, and the next activation deletes it.
4. For the retry messages, filter the General log on `HDBResale_Core.Sync`.

## 4. Wrong data was activated

In SyncAdmin, click *Roll back to previous snapshot*. It takes seconds and is written to the audit log. Then investigate the bad run using steps 2 and 3.

## Afterwards

- Make sure the alarm is back to OK.
- Write down what happened and how long recovery took.
- If one of the checks should have caught the problem, add a test for it.
