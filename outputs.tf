output "env" {
  value = var.env
}

output "iam_user_access_keys" {
  value = { for user in local.users : user.name => {
    access_key_id     = aws_iam_access_key.users[user.name].id,
    secret_access_key = aws_iam_access_key.users[user.name].secret,
  } }
  sensitive = true
}

output "postgresql_user_logins" {
  value = {
    alprs_user = local.alprs_pass
    atlas_user = local.atlas_pass
  }
  sensitive = true
}

output "rundeck_admin_pass" {
  value     = local.rundeck_pass
  sensitive = true
}

# bastion_ami_id:               bastion.tf
# bastino_ami_name:             bastion.tf
# bastion_instance_id:          bastion.tf
# postgresql_ami_id:            postgresql.tf
# postgresql_ami_name:          postgresql.tf
# postgresql_instance_id:       postgresql.tf
# postgresql_private_domain:    postgresql.tf
# postgresql_private_ip:        postgresql.tf
# elasticsearch_ami_id:         elasticsearch.tf
# elasticsearch_ami_name:       elasticsearch.tf
# elasticsearch_instance_id:    elasticsearch.tf
# elasticsearch_private_domain: elasticsearch.tf
# elasticsearch_private_ip:     elasticsearch.tf
# conductor_ami_id:             conductor.tf
# conductor_ami_name:           conductor.tf
# conductor_instance_id:        conductor.tf
# conductor_private_domain:     conductor.tf
# conductor_private_ip:         conductor.tf
# datastore_ami_id:             datastore.tf
# datastore_ami_name:           datastore.tf
# datastore_instance_id:        datastore.tf
# datastore_private_domain:     datastore.tf
# datastore_private_ip:         datastore.tf
# indexer_ami_id:               indexer.tf
# indexer_ami_name:             indexer.tf
# indexer_instance_id:          indexer.tf
# indexer_private_domain:       indexer.tf
# indexer_private_ip:           indexer.tf
# worker_ami_id:                worker.tf
# worker_ami_name:              worker.tf
# worker_instance_id:           worker.tf
# worker_private_domain:        worker.tf
# worker_private_ip:            worker.tf
# app_cf_domain:                cloudfront.tf
# api_elb_domain:               elb.tf
