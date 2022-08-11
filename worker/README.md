### Caveats

* Do NOT replace hardcoded strings "`https://api.openlattice.com`"
  (often as the default value of the `base_url` function argument)
  anywhere within the `olpy` and `pyntegrationsncric` directories
  because they will be replaced automatically with the proper API
  endpoint (for dev or prod environments) by the `mkwhl.sh` script.
