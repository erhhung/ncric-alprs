# PostgreSQL Notes

## User Passwords

Obtain auto-generated database user passwords by running this command  
_(passwords will never change unless the stack or "`keys.tf`" is recreated)_:

```bash
$ ./tf.sh output postgresql_user_logins
{
  "alprs_user" = "foobarbaz"
  "atlas_user" = "foobarbaz"
}
```

## Cron Jobs

Three scripts are installed across the PostgreSQL instances in "`/var/lib/postgresql`" (home directory of the `postgres` user)  
to accompany corresponding cron job definitions in "`/etc/cron.d`".

* "`backup-all.sh`" **_(currently disabled and replaced by AWS Backup)_** — archives all databases to S3 using `pg_basebackup`  
  _(creates and mounts a temporary EBS volume of the **same size** as "`/opt/postgresql/data`" at "`/opt/postgresql/temp`")._

* "`backup-flock.sh`" (on host "`postgresql2`" only; runs daily at 2:20am) — archives raw data in "flock_reads\__dow_" tables  
  that are older than the retention period (currently 3 days) to S3, and then deletes them from the tables; also runs `pg_repack`  
  on the purged tables to reclaim disk space.

* "`drop-temps.sh`" (on host "`postgresql2`" only; runs daily at 4:20am) — deletes "forgotten" temporary integration tables  
  (likely due to failed Rundeck jobs) (e.g. "`boss4_catchup_2022_9_30_22_5_33`") in the Atlas database that are older than  
  the retention period (currently 3 days).

Logs from each script can be found in "`/opt/postgresql`" _(`$PG_HOME`)_.

## Storage

The PostgreSQL data volume is an **XFS-formatted volume** mounted at "`/opt/postgresql`":

```bash
$ df -h /opt/postgresql
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1    120G  1.1G  119G   1% /opt/postgresql
```

In order to expand storage to accommodate ongoing growth, perform the following steps:

1. Set a larger `data_volume_sizes.postgresql` value in "`config/prod.tfvars`".
2. Run `terraform apply -var-file config/prod.tfvars -target aws_ebs_volume.postgresql_data[0]`  
   ("`[0]`" for host "`postgresql1`" or "`[1]`" for host "`postgresql2`") to grow the EBS volume.
3. SSH into the PostgreSQL host and run the following commands:

    ```bash
    # for example, grow data volume from 120G to 150G
    ubuntu@alprsprod-postgresql1:~$ df -h /opt/postgresql
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme1n1    120G  1.1G  119G   1% /opt/postgresql

    # confirm that the EBS disk has been enlarged
    ubuntu@alprsprod-postgresql1:~$ lsblk /dev/nvme1n1
    NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
    nvme1n1 259:3    0  150G  0 disk /opt/postgresql

    # no need to unmount volume as XFS is
    # capable of growing a mounted volume
    ubuntu@alprsprod-postgresql1:~$ sudo xfs_growfs /opt/postgresql
    meta-data=/dev/nvme1n1           isize=512    agcount=16, agsize=1966080 blks
             =                       sectsz=512   attr=2, projid32bit=1
             =                       crc=1        finobt=1, sparse=1, rmapbt=0
             =                       reflink=1
    data     =                       bsize=4096   blocks=31457280, imaxpct=25
             =                       sunit=1      swidth=1 blks
    naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
    log      =internal log           bsize=4096   blocks=15360, version=2
             =                       sectsz=512   sunit=1 blks, lazy-count=1
    realtime =none                   extsz=4096   blocks=0, rtextents=0
    data blocks changed from 31457280 to 39321600

    # confirm that the XFS volume has been enlarged
    ubuntu@alprsprod-postgresql1:~$ df -h /opt/postgresql
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme1n1    150G  1.3G  149G   1% /opt/postgresql
    ```

    _If the PostgreSQL host is redeployed at the same time, then file
    system expansion will occur automatically via "`/bootstrap.sh`"._

## Table Sizes

Run the example queries on [this wiki](https://wiki.postgresql.org/wiki/Disk_Usage)
to show the sizes taken up by individual tables in a database.

```sql
WITH RECURSIVE pg_inherit(inhrelid, inhparent) AS
    (select inhrelid, inhparent
    FROM pg_inherits
    UNION
    SELECT child.inhrelid, parent.inhparent
    FROM pg_inherit child, pg_inherits parent
    WHERE child.inhparent = parent.inhrelid),
pg_inherit_short AS (SELECT * FROM pg_inherit WHERE inhparent NOT IN (SELECT inhrelid FROM pg_inherit))
SELECT table_schema
    , TABLE_NAME
    , row_estimate
    , pg_size_pretty(total_bytes) AS total
    , pg_size_pretty(index_bytes) AS INDEX
    , pg_size_pretty(toast_bytes) AS toast
    , pg_size_pretty(table_bytes) AS TABLE
    , total_bytes::float8 / sum(total_bytes) OVER () AS total_size_share
  FROM (
    SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
    FROM (
         SELECT c.oid
              , nspname AS table_schema
              , relname AS TABLE_NAME
              , SUM(c.reltuples) OVER (partition BY parent) AS row_estimate
              , SUM(pg_total_relation_size(c.oid)) OVER (partition BY parent) AS total_bytes
              , SUM(pg_indexes_size(c.oid)) OVER (partition BY parent) AS index_bytes
              , SUM(pg_total_relation_size(reltoastrelid)) OVER (partition BY parent) AS toast_bytes
              , parent
          FROM (
                SELECT pg_class.oid
                    , reltuples
                    , relname
                    , relnamespace
                    , pg_class.reltoastrelid
                    , COALESCE(inhparent, pg_class.oid) parent
                FROM pg_class
                    LEFT JOIN pg_inherit_short ON inhrelid = oid
                WHERE relkind IN ('r', 'p')
             ) c
             LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
  ) a
  WHERE oid = parent
) a
ORDER BY total_bytes DESC;
```

## "`alprs.sql`"

"`alprs.sql`" is a carefully curated SQL script to bootstrap an empty
`alprs` database.  
It contains the required EDM objects, configured NCRIC organization,
its roles and entity sets for select agencies, permissions granted
to select roles and admin users, and app settings.  
To maintain its lean size, it **should never contain any ingested
ALPR data**!

To export an updated "`alprs.sql.gz`", perform the following steps:

1. Reprovision a **clean** environment without any ingested data.
2. Make state changes to the database, such as adding entity sets
   and modifying permissions.
3. Stop all apps that may cause database changes, including Conductor,
   Datastore, Indexer, Rundeck jobs, Shuttle and Flapper processes.

    ```bash
    $ ./stop.sh bastion worker indexer datastore conductor

    Stop services on hosts:
      * bastion
      * worker
      * indexer
      * datastore
      * conductor
    Proceed? [y/N] y

    Retrieving Terraform output variables...DONE.
    Stopping services on host "bastion"...DONE.
    Stopping services on host "worker"...DONE.
    Stopping services on host "indexer"...DONE.
    Stopping services on host "datastore"...DONE.
    Stopping services on host "conductor"...DONE.
    ```

4. Run the following commands:

    ```bash
    $ ssh alprsdevpg1

      ubuntu@alprsdev-postgresql1:~$ psql
                    postgres@alprs=# UPDATE ids SET last_index = '-infinity';
                    postgres@alprs=# \q
      ubuntu@alprsdev-postgresql1:~$ sudo su postgres bash -c "pg_dump alprs" > alprs.sql
      ubuntu@alprsdev-postgresql1:~$ gzip -k9 alprs.sql
      ubuntu@alprsdev-postgresql1:~$ exit

    $ scp alprsdevpg1:alprs.sql.gz .
    ```

## "`ncric.sql`"

"`ncric.sql`" is a curated SQL script to bootstrap an empty NCRIC
`org_1446ff84711242ec828df181f45e4d20` (aka "Atlas") database.  
It contains, at present, without any ingested ALPR data, only the
`standardized_agency_names` table in the `integrations` schema.

To export an updated "`ncric.sql.gz`", perform the following steps:

1. Run the following commands:

    ```bash
    $ ssh alprsdevpg2

    ubuntu@alprsdev-postgresql2:~$ sudo su postgres bash -c "pg_dump -C --no-acl \
                                     -n integrations -T 'boss4*' -T 'flock*' -T 'scso*' \
                                     org_1446ff84711242ec828df181f45e4d20" > ncric.sql

    ubuntu@alprsdev-postgresql2:~$ sudo su postgres bash -c "pg_dump -s --no-acl \
                                     -n integrations -t 'flock_reads*' \
                                     org_1446ff84711242ec828df181f45e4d20" > ncric2.sql
    ```

2. Edit "`ncric.sql`" and **sort the lines** containing
   data for the `standardized_agency_names` table.
3. Manually merge "`ncric2.sql`" into "`ncric.sql`".
4. Run the following commands:

    ```bash
      ubuntu@alprsdev-postgresql2:~$ gzip -k9 ncric.sql
      ubuntu@alprsdev-postgresql2:~$ exit

    $ scp alprsdevpg2:ncric.sql.gz .
    ```
