Shuttle
-------

Shuttle is a CLI app deployed on the Rundeck worker node
for Rundeck jobs to integrate ALPR reads from S3 (BOSS4
or SCSO) or from the "Atlas" staging database (Flock API
reads) into the primary "Black Panther" database, where
it will be indexed to allow end-user queries.
