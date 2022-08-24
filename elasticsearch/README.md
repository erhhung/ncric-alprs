Elasticsearch
-------------

## Storage

The Elasticsearch data volume is an **XFS-formatted volume** mounted at `/opt/elasticsearch`:

```bash
$ df -h /opt/elasticsearch
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1     30G  356M   30G   2% /opt/elasticsearch
```

In order to expand storage to accommodate ongoing growth, perform the following steps:

1. Set a larger `data_volume_sizes.elasticsearch` value in "`config/prod.tfvars`".
2. Run `terraform apply -var-file config/prod.tfvars -target aws_ebs_volume.elasticsearch_data` to grow the EBS volume.
3. SSH into the Elasticsearch host and run the following commands:
    ```bash
    # for example, grow data volume from 30G to 50G
    ubuntu@alprsprod-elasticsearch:~$ df -h /opt/elasticsearch
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme1n1     30G  356M   30G   2% /opt/elasticsearch

    # confirm that the EBS disk has been enlarged
    ubuntu@alprsprod-elasticsearch:~$ lsblk /dev/nvme1n1
    NAME    MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
    nvme1n1 259:3    0  50G  0 disk /opt/elasticsearch

    # no need to unmount volume as XFS is
    # capable of growing a mounted volume
    ubuntu@alprsprod-elasticsearch:~$ sudo xfs_growfs /opt/elasticsearch
    meta-data=/dev/nvme1n1           isize=512    agcount=16, agsize=491520 blks
             =                       sectsz=512   attr=2, projid32bit=1
             =                       crc=1        finobt=1, sparse=1, rmapbt=0
             =                       reflink=1
    data     =                       bsize=4096   blocks=7864320, imaxpct=25
             =                       sunit=1      swidth=1 blks
    naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
    log      =internal log           bsize=4096   blocks=3840, version=2
             =                       sectsz=512   sunit=1 blks, lazy-count=1
    realtime =none                   extsz=4096   blocks=0, rtextents=0
    data blocks changed from 7864320 to 13107200

    # confirm that the XFS volume has been enlarged
    ubuntu@alprsprod-elasticsearch:~$ df -h /opt/elasticsearch
    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme1n1     50G  502M   50G   1% /opt/elasticsearch
    ```
