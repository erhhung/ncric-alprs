## Important!

* Do NOT change hardcoded strings "`http://datastore:8080`"
  (often as the default value of the `base_url` function argument)
  anywhere within the `olpy` and `pyntegrationsncric` directories
  because they may be replaced automatically with the proper API
  endpoint (for dev or prod environments) by the `mkwhl.sh` script.
* Do NOT change hardcoded strings "`us-gov-west-1`" (boto3 Session
  `region_name` parameter) as they will also be replaced with the
  appropriate region by the `mkwhl.sh` script.
