## AWS Backup

When destroying both the AWS Backup plan and the vault,
Terraform apply may fail due to the following error:

```yaml
Error: deleting Backup Vault (alprs-backups): InvalidRequestException:
Backup vault cannot be deleted because it contains recovery points.
```

AWS Backup will not automatically delete EBS snapshots,
a.k.a. recovery points. That must be done manually:

```bash
while read arn; do
  echo Deleting: $arn
  aws backup delete-recovery-point \
    --backup-vault-name alprs-backups \
    --recovery-point-arn $arn
done < <(
  aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name alprs-backups \
    --query 'RecoveryPoints[].[RecoveryPointArn]' \
    --output text
)
```
