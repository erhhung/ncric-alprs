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

output "app_cf_domain" {
  value = aws_cloudfront_distribution.app.domain_name
}

output "api_elb_domain" {
  value = aws_lb.api.dns_name
}

# bastion_instance_id:          bastion.tf
# postgresql_instance_id:       postgresql.tf
# postgresql_private_domain:    postgresql.tf
# postgresql_private_ip:        postgresql.tf
# elasticsearch_instance_id:    elasticsearch.tf
# elasticsearch_private_domain: elasticsearch.tf
# elasticsearch_private_ip:     elasticsearch.tf
# conductor_instance_id:        conductor.tf
# conductor_private_domain:     conductor.tf
# conductor_private_ip:         conductor.tf
# datastore_instance_id:        datastore.tf
# datastore_private_domain:     datastore.tf
# datastore_private_ip:         datastore.tf
# indexer_instance_id:          indexer.tf
# indexer_private_domain:       indexer.tf
# indexer_private_ip:           indexer.tf
