# ALPRS AWS Infra

## AWS Environment

### AWS Systems Manager

* **Quick Setup**
  * Enable all **Host Management** configuration options

## Terraform State

Create S3 bucket for Terraform to store its state:

```bash
aws s3api create-bucket \
  --profile alprscom
  --bucket alprs-tfstates-dev \
  --create-bucket-configuration "LocationConstraint=us-west-2" \
  --object-ownership BucketOwnerEnforced

aws s3api put-public-access-block \
  --profile alprscom
  --bucket alprs-tfstates-dev \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**_Assumes AWS CLI profiles `alprscom` and `alprsgov` already exists!_**

## Terraform Init

```bash
terraform init -backend-config config/dev.conf -upgrade
```

## Terraform Apply

```bash
terraform plan  -var-file config/dev.tfvars -compact-warnings
terraform apply -var-file config/dev.tfvars -compact-warnings
```
