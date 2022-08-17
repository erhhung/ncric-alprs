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
