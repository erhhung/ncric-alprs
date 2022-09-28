## CloudWatch Agent

Install updated configuration:
```bash
sudo su -l
CWAGENT_HOME=/opt/aws/amazon-cloudwatch-agent
aws s3 cp s3://$(hostname | sed -En 's|^alprs([^-]+)-(.+)$|alprs-infra-\1/userdata/\2|p')/cwagent.json $CWAGENT_HOME/etc/amazon-cloudwatch-agent.json
$CWAGENT_HOME/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:$CWAGENT_HOME/etc/amazon-cloudwatch-agent.json
logout
```
