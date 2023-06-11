# Standardized Agency Names

## "integrations.standardized_agency_names" Table

```bash
$ scp standardized_agency_names.csv alprsdevpg2:.
$ ssh alprsdevpg2

ubuntu@alprsdev-postgresql2:~$ psql "-c \"DELETE FROM integrations.standardized_agency_names\""
ubuntu@alprsdev-postgresql2:~$ psql "-c \"SELECT COUNT(*) FROM integrations.standardized_agency_names\""
 count
-------
     0
(1 row)

ubuntu@alprsdev-postgresql2:~$ psql "-c \"COPY integrations.standardized_agency_names(\\\"ol.name\\\",standardized_agency_name,\\\"ol.datasource\\\")
                                          FROM '$(pwd)standardized_agency_names.csv' DELIMITER ',' CSV HEADER\""
ubuntu@alprsdev-postgresql2:~$ psql "-c \"SELECT COUNT(*) FROM integrations.standardized_agency_names\""
 count
-------
   203
(1 row)
```
