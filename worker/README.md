## Important!

* Do NOT change hardcoded strings "`http://datastore:8080`"
  (often as the default value of the `base_url` function argument)
  anywhere within the `olpy` and `pyntegrationsncric` directories
  because they may be replaced automatically with the proper API
  endpoint (for dev or prod environments) by the `mkwhl.sh` script.
* Do NOT change hardcoded strings "`us-gov-west-1`" (boto3 Session
  `region_name` parameter) as they will also be replaced with the
  appropriate region by the `mkwhl.sh` script.

## Update Packages

To update `olpy` and `pyntegrationsncric` packages on the Worker
after Terraform apply, run the following via SSH:

```bash
(
cd ~/packages
eval $(egrep "(S3_URL)=\"" /bootstrap.sh | awk '{print $2}')
aws s3 sync $S3_URL/worker . --exclude '*' --include '*.whl' --no-progress

for wheel in pyntegrationsncric olpy; do
  whl=$(unzip -l $wheel.whl | sed -En "s|.+($wheel-[0-9.]+)\.dist-info/WHEEL|\1-py3-none-any.whl|p")
  mv -f $wheel.whl $whl && pip3 install --force-reinstall $whl
done
)
```

## Useful Queries

_Enter the `pgcli` prompt by running either `alprs` or `atlas`
(Bash functions defined in "`~/.bash_aliases`"), depending on
which database you'd like to connect to._

Show number of Flock reads per day:
```sql
SELECT DISTINCT(timestamp::date) AS date,
  COUNT(*) OVER (PARTITION BY timestamp::date) AS count
FROM (
  SELECT timestamp FROM integrations.flock_reads_sun UNION
  SELECT timestamp FROM integrations.flock_reads_mon UNION
  SELECT timestamp FROM integrations.flock_reads_tue UNION
  SELECT timestamp FROM integrations.flock_reads_wed UNION
  SELECT timestamp FROM integrations.flock_reads_thu UNION
  SELECT timestamp FROM integrations.flock_reads_fri UNION
  SELECT timestamp FROM integrations.flock_reads_sat) AS _table
ORDER BY timestamp::date;
```
