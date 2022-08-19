Submodule "`userdata`"
----------------------

Uploads user data files to S3 for instance bootstrapping.

## Inputs

* "`bucket`" _(required)_ — Name of backend config bucket (e.g. "`alprs-infra-dev`")
* "`files`" _(required)_ — List of files to upload under S3 prefix "`userdata/`"

Each file is an object containing these properties:

* "`path`" _(required)_ — Path under "`userdata/`"
* "`file`" _(either this or "`data`" is required)_ — Path to **local file**
* "`data`" _(either this or "`file`" is required)_ — File **content string**
* "`type`" _(optional)_ — Content type (default is "`text/plain`")

## Outputs

_None_
