Submodule "`vpc`"
-----------------

Provisions a VPC network with public and private subnets.

## Inputs

* "`vpc_name`" _(optional)_ — Name of VPC (default is "`Main`")
* "`cidr_block`" _(optional)_ — VPC CIDR block (default is "`10.0.0.0/16`")
* "`subnet_cidrs`" _(required)_ — VPC subnet CIDRs: `{public:[...], private:[...]}`

## Outputs

* "`vpc_id`"
* "`subnet_ids`" — `{public1:"", private1:"", ...}`
