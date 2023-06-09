NCRIC Entity Sets
-----------------

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

_**NOTE**: These entity sets are already reflected in the PostgreSQL init script "`alprs.sql`"._

```json
[
  {
    "entityTypeId": "e33ad963-60fd-489d-8cdb-9faca522e18a",
    "name": "NCRICAgencies",
    "title": "NCRICAgencies",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "65416b16-626c-495a-9904-a22a4d113276",
    "name": "NCRICCollectedBy",
    "title": "NCRICCollectedBy",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "6b513215-2566-491c-9d08-02a282f4123e",
    "name": "NCRICImageSources",
    "title": "NCRICImageSources",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "9b44a35d-d414-4f7e-929a-92175017b809",
    "name": "NCRICRecordedBy",
    "title": "NCRICRecordedBy",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "e33ad963-60fd-489d-8cdb-9faca522e18a",
    "name": "NCRICStandardizedAgencies",
    "title": "NCRICStandardizedAgencies",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsAlamedaCountySO",
    "title": "Alameda County SO",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsAndersonCityPD",
    "title": "Anderson City PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsAthertonPD",
    "title": "Atherton PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsBayAreaRapidTransit",
    "title": "Bay Area Rapid Transit",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsBeniciaPD",
    "title": "Benicia PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsBeverlyHillsPD",
    "title": "Beverly Hills PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsBrisbanePD",
    "title": "Brisbane PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsCHP",
    "title": "CHP",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsCampbellPD",
    "title": "Campbell PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsCentralMarinPA",
    "title": "Central Marin PA",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsCeresPD",
    "title": "Ceres PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsChicoPD",
    "title": "Chico PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsColmaPD",
    "title": "Colma PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsDalyCityPD",
    "title": "Daly City PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsDanvillePD",
    "title": "Danville PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsDixonPD",
    "title": "Dixon PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsFairfieldPD",
    "title": "Fairfield PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsFremontPD",
    "title": "Fremont PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsGGBVistaPoint",
    "title": "GGB Vista Point",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsGilroyPD",
    "title": "Gilroy PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsHIDTA",
    "title": "HIDTA",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsHPD",
    "title": "HPD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsHaywardPD",
    "title": "Hayward PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsHerculesPD",
    "title": "Hercules PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsHillsboroughPD",
    "title": "Hillsborough PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsHumboldtCounty",
    "title": "Humboldt County",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsKaiserPermanente",
    "title": "Kaiser Permanente",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsLivermorePD",
    "title": "Livermore PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsLosAltosPD",
    "title": "Los Altos PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsManualEntries",
    "title": "Manual Entries",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsMarinCC",
    "title": "Marin CC",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsMenloParkPD",
    "title": "Menlo Park PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsMillbraePD",
    "title": "Millbrae PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsModestoPD",
    "title": "Modesto PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsMorganHillPD",
    "title": "Morgan Hill PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsNCRIC",
    "title": "NCRIC",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsNPD",
    "title": "NPD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsNapaPD",
    "title": "Napa PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsNewarkPD",
    "title": "Newark PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsNovatoPD",
    "title": "Novato PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsOakleyPD",
    "title": "Oakley PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsOrindaPD",
    "title": "Orinda PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsPaloAltoPD",
    "title": "Palo Alto PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsPiedmontPD",
    "title": "Piedmont PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsPleasantonPD",
    "title": "Pleasanton PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsRioVistaPD",
    "title": "Rio Vista PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsRocklinPD",
    "title": "Rocklin PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSFOAirportPolice",
    "title": "SFO Airport Police",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSalinasPD",
    "title": "Salinas PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanBrunoPD",
    "title": "San Bruno PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanFranciscoPD",
    "title": "San Francisco PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanJoaquinCountySO",
    "title": "San Joaquin County SO",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanLeandroPD",
    "title": "San Leandro PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanMateoCountySO",
    "title": "San Mateo County SO",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanMateoPD",
    "title": "San Mateo PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanMateoVTTF",
    "title": "San Mateo VTTF",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSanRamonPD",
    "title": "San Ramon PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSantaClaraCountySO",
    "title": "Santa Clara County SO",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSantaClaraPD",
    "title": "Santa Clara PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSantaClaraSheriff",
    "title": "Santa Clara Sheriff",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsShastaCountySO",
    "title": "Shasta County SO",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSolanoCountySO",
    "title": "Solano County SO",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSouthSanFranciscoPD",
    "title": "South San Francisco PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSuisunPD",
    "title": "Suisun PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSunnyvaleDPS",
    "title": "Sunnyvale DPS",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsSunnyvalePD",
    "title": "Sunnyvale PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsV5Sys",
    "title": "V5Sys",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsVacavillePD",
    "title": "Vacaville PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsVallejoPD",
    "title": "Vallejo PD",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  },
  {
    "entityTypeId": "3c6dad54-c4b4-4dfb-bd8b-d8dd56e342ec",
    "name": "NCRICVehicleRecordsYosemiteNationalPark",
    "title": "Yosemite National Park",
    "organizationId": "1446ff84-7112-42ec-828d-f181f45e4d20",
    "contacts": [
      "devops@astrometrics.us"
    ],
    "flags": []
  }
]
```
