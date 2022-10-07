## Terraform Commands

* List managed objects in the current Terraform state:
  ```bash
  ./tf.sh state list
  ```

* Ask Terraform to "forget" a resource (useful for retaining, for example,
  the existing PostgreSQL data volume while creating a new, smaller volume
  to migrate to):
  ```bash
  $ ./tf.sh state rm aws_volume_attachment.postgresql_data \
                     aws_ebs_volume.postgresql_data

  Removed aws_volume_attachment.postgresql_data
  Removed aws_ebs_volume.postgresql_data
  Successfully removed 2 resource instance(s).
  ```
