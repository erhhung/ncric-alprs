## Job Definitions

Job definition files under "[`project/rundeck-AstroMetrics/jobs`
](project/rundeck-AstroMetrics/jobs)" come in `.xml` and `.yaml`
formats.  
The YAML format is only kept because they are easier to read and
can be imported into Rundeck individually,  
but do not actually get packaged into "`astrometrics.rdproject.jar`"
because the CLI command  
"`rd projects archives import`" only looks for `.xml` files in
a `.jar` archive.  
Nevertheless, please keep both formats in sync when making job
modifications.

## Update Jobs

To update Rundeck job definitions from the Bastion host after
Terraform apply, run the following via SSH:

```bash
(
cd ~/rundeck
proj=AstroMetrics

jar="${proj,,}_$(date "+%F").rdproject.jar"
args=(-p $proj -f $jar -i jobs -i configs -i executions)
rd projects archives export ${args[*]}
aws s3 cp $jar s3://$BACKUP_BUCKET/rundeck/$jar --no-progress

jar="${proj,,}.rdproject.jar"
eval $(egrep "(ENV|S3_URL)=\"" /bootstrap.sh | awk '{print $2}')
aws s3 cp "$S3_URL/rundeck/$jar" . --no-progress
rd projects archives import -f $jar -p $proj

if [ "$ENV" == dev ]; then
  jobs=($(rd jobs list -% "%id %name" | \
              awk '{if ($2 == "Recurring") print $1}'))
  rd jobs unschedulebulk -i $(IFS=,; echo "${jobs[*]}") -y
fi
)
```
