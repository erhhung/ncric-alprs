PostgreSQL
----------

## Storage

The PostgreSQL data volume is an **XFS-formatted volume** mounted at `/opt/postgresql`:

```bash
$ df -h /opt/postgresql
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1    120G  1.1G  119G   1% /opt/postgresql
```

In order to expand storage to accommodate ongoing growth, perform the following steps:

1. Set a larger `data_volume_sizes.postgresql` value in "`config/prod.tfvars`".
2. Run `terraform apply -var-file config/prod.tfvars -target aws_ebs_volume.postgresql_data` to grow the EBS volume.
3. SSH into the PostgreSQL host and run the following commands:
    ```bash
    # for example, grow data volume from 120G to 150G
    ubuntu@alprsprod-postgresql:~$ df -h /opt/postgresql
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme1n1    120G  1.1G  119G   1% /opt/postgresql

    # confirm that the EBS disk has been enlarged
    ubuntu@alprsprod-postgresql:~$ lsblk /dev/nvme1n1
    NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
    nvme1n1 259:3    0  150G  0 disk /opt/postgresql

    # no need to unmount volume as XFS is
    # capable of growing a mounted volume
    ubuntu@alprsprod-postgresql:~$ sudo xfs_growfs /opt/postgresql
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
    ubuntu@alprsprod-postgresql:~$ df -h /opt/postgresql
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme1n1    150G  1.3G  149G   1% /opt/postgresql
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
4. Run the following commands:
    ```bash
    $ ssh alprsdevpg

      ubuntu@alprsdev-postgresql:~$ psql
    postgres@org_1446ff84711242ec828df181f45e4d20=# \c alprs
                   postgres@alprs=# UPDATE ids SET last_index = '-infinity';
                   postgres@alprs=# \q
      ubuntu@alprsdev-postgresql:~$ sudo su postgres bash -c "pg_dump alprs" > alprs.sql
      ubuntu@alprsdev-postgresql:~$ gzip -k9 alprs.sql
      ubuntu@alprsdev-postgresql:~$ exit

    $ scp alprsdevpg:alprs.sql.gz .
    ```

## "`ncric.sql`"

"`ncric.sql`" is a curated SQL script to bootstrap an empty NCRIC
`org_1446ff84711242ec828df181f45e4d20` (aka "Atlas") database.  
It contains, at present, without any ingested ALPR data, only the
`standardized_agency_names` table in the `integrations` schema.

To export an updated "`ncric.sql.gz`", perform the following steps:

1. Run the following commands:
    ```bash
    $ ssh alprsdevpg

    ubuntu@alprsdev-postgresql:~$ sudo su postgres bash -c "pg_dump -C --no-acl \
                                    -n integrations -T 'boss4*' -T 'flock*' -T 'scso*' \
                                    org_1446ff84711242ec828df181f45e4d20" > ncric.sql
    ```
2. Edit "`ncric.sql`" and **sort the lines** containing
   data for the `standardized_agency_names` table.
3. Run the following commands:
    ```bash
      ubuntu@alprsdev-postgresql:~$ gzip -k9 ncric.sql
      ubuntu@alprsdev-postgresql:~$ exit

    $ scp alprsdevpg:ncric.sql.gz .
    ```
