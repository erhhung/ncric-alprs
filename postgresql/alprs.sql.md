`alprs.sql`
-----------

To export an updated "`alprs.sql`", first reprovision a **clean**
environment without any vehicle data, then make state changes like
adding entity sets or modifying permissions, then follow these steps:

```bash
$ ssh alprsdevpg

  ubuntu@alprsdev-postgresql:~$ sudo su -l postgres
postgres@alprsdev-postgresql:~$ pg_dump alprs > alprs.sql
postgres@alprsdev-postgresql:~$ exit
  ubuntu@alprsdev-postgresql:~$ sudo cp /var/lib/postgresql/alprs.sql .
  ubuntu@alprsdev-postgresql:~$ sudo chown ubuntu:ubuntu alprs.sql
  ubuntu@alprsdev-postgresql:~$ gzip -k9 alprs.sql
  ubuntu@alprsdev-postgresql:~$ exit

$ scp alprsdevpg:alprs.sql.gz .
```
