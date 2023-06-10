# NCRIC Entity Sets

## Command

```bash
CLIENT_ID="kJBCfaEo0bUzBSpZJUPy4N5Jkpn4sZP4"
auth0_domain="maiveric.us.auth0.com"
auth0_email="ol@dev.astrometrics.us"
auth0_pass="..."

params=(
  client_id=$CLIENT_ID
  grant_type=password
  username=$auth0_email
  password=$auth0_pass
  audience=https://$auth0_domain/userinfo
  scope=openid
)
jwt=$(curl -sX POST https://$auth0_domain/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "$(IFS=\&; echo "${params[*]}")" | jq -r .id_token)

# use http://datastore:8080/ if running on Indexer host
cat <<'EOF' | curl -s -d @- -H "Authorization: Bearer $jwt" \
                            -H "Content-Type: application/json" \
                      https://api.dev.astrometrics.us/datastore/entity-sets \
            | jq
__SEE_PAYLOAD_SECTION__
EOF

# trigger indexing of all EDM objects
curl -s -H "Authorization: Bearer $jwt" \
        -o /dev/null -w '%{http_code}\n' \
  http://datastore:8080/datastore/search/edm/index
```

## Permissions

It is imperative that all entity sets (at current count there should be 108) are granted
proper permissions using the **Lattice Orgs** webapp (http://localhost:9001/ after SSH
tunneling into the **bastion host**):

1. Log into Lattice Orgs as **ol@dev.astrometrics.us**
2. Select the **NCRIC organization**
3. Select **Manage Permissions** from the **⋮** icon to the right of the NCRIC title
4. Make sure relevant admin and owner users are granted proper permissions
    * Admin users: "NCRIC - ADMIN", ol@dev.astrometrics.us, ol@astrometrics.us, eyuan@maiveric.com, mashiq@maiveric.com
        * Grant `owner`, `read`, `write`, `integrate`, `link`, `materialize`
    * Owner users: brodrigues@ncric.ca.gov, agent.blue@maiveric.com
        * Grant `owner`, `read`, `write`
5. Go back to the NCRIC organization view and select **People** at the top
6. Grant the same set of admin users **all 4 roles** and the owners all roles except "`NCRIC - ADMIN`"
    * All roles: "`NCRIC - ADMIN`", "`AstroMetrics - OWNER`", "`AstroMetrics - READ`", "`AstroMetrics - WRITE`"
7. Repeat for **each admin user** (excluding owner users):
    1. Select the user to show user view
    2. Under **Data Sets**, there are 10 entity sets listed "per page", and there are currently 108
    3. If new entity sets have been added, click on the **Add data set** button and select those new entity sets (search might help)
    4. On the **Assign Permissions To Data Sets** page of the dialog, select all 6 permissions and click **Continue**
    5. Retry the process if, for some reason, the dialog shows that an error has occurred
8. Go back to the NCRIC organization view and select **Roles** at the top
9. Repeat for **each role**:
    1. Select the role to show role view
    2. Under **Data Sets**, there are 10 entity sets listed "per page", and there are currently 108
    3. If new entity sets have been added, click on the **Add data set** button and select those new entity sets (search might help)
    4. On the **Assign Permissions To Data Sets** page of the dialog, select the permissions relevant to the role and click **Continue**
        * "**`NCRIC - ADMIN`**": `owner`, `read`, `write`, `integrate`, `link`, `materialize`
        * "**`AstroMetrics - OWNER`**": `owner`, `read`, `write`
        * "**`AstroMetrics - READ`**": `read`
        * "**`AstroMetrics - WRITE`**": `write`
    5. Retry the process if, for some reason, the dialog shows that an error has occurred
10. Go back to the NCRIC organization view and verify that **all (currently 108) entity sets appear** on the **Data Sets** tab

## Payload

Generate JSON payload with entity sets derived from standardized agency names that have not been added to the database:

```bash
# brew install jq jo
# npm i -g csvtojson

alprs_sql=/tmp/alprs.sql
gunzip -c ../postgresql/alprs.sql.gz > $alprs_sql

while read es_id es_name; do
  if egrep -q "\b$es_id\b" $alprs_sql; then
    echo >&2 "$es_id already exists."
  else
    jo entityTypeId='3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec' \
       name="$es_id" \
       title="$es_name" \
       organizationId='1446ff84-7112-42ec-828d-f181f45e4d20' \
       contacts='["devops@astrometrics.us"]' \
       flags='[]'
  fi
done < <(
  csvtojson standardized_agency_names.csv | \
    jq -r '[.[].standardized_agency_name] | unique[] |
               "NCRICVehicleRecords\(gsub(" ";"")) \(.)"'
) | jq -s . | \
    tee missing_entity_sets.json

rm $alprs_sql
```

_**NOTE**: "[**`entity_sets.json`**](./entity_sets.json)" contains entity
sets that are already reflected in the PostgreSQL init script "`alprs.sql`"._
