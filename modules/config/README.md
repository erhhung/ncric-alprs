Submodule "`config`"
--------------------

Uploads config files to S3, optionally rendering templated YAML files.

## Inputs

* "`service`" _(required)_ — Service name used as the S3 prefix "`<service>/`"  
  (one of "`conductor`", "`datastore`", "`indexer`", "`shuttle`", "`flapper`")
* "`path`" _(required)_ — Path to folder containing config files
* "`bucket`" _(required)_ — Target config bucket (e.g. "`alprs-config-dev`")
* "`values`" _(optional)_ — Placeholder values for YAML templates

`values` is a map of string values for placeholders of the form `${<key>}` (e.g. `${POSTGRESQL_HOST}`).

## Outputs

* "`module_paths`" _(for debugging)_ — `{cwd:"<abspath_git_root>", module:"modules/config", root:"."}`
