# ALPRS AWS Infra

## Local Environment

Add to "`~/.bash_profile`":

```bash
export TF_CLI_ARGS_init="-compact-warnings -upgrade"
export TF_CLI_ARGS_plan="-compact-warnings"
export TF_CLI_ARGS_apply="-compact-warnings"
```

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
terraform init -backend-config config/dev.conf
```

## Terraform Apply

```bash
terraform plan  -var-file config/dev.tfvars
terraform apply -var-file config/dev.tfvars
```
