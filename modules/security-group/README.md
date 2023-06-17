Submodule "`security-group`"
----------------------------

Provisions a network security group in the VPC.

## Inputs

* "`name`" _(required)_ — Security group name
* "`description`" _(required)_ — Security group description
* "`vpc_id`" _(required)_ — ID of associated VPC
* "`rules`" _(optional)_ — Additional (ingress) rules **besides "egress all"**

`rules` is a map of objects: key must be named "<`ingress`|`egress`>`_`\<_ports_>"; value contains these properties:

* "`from_port`" _(required)_ — From port number in range (inclusive)
* "`to_port`" _(optional)_ — To port number in range (inclusive) (default is `from_port`)
* "`protocol`" _(optional)_ — "`tcp`" or "`udp`" (default is "`tcp`")
* "`cidr_blocks`" _(required)_ — List of source (ingress) or destination (egress) CIDR blocks

## Outputs

* "`id`"
