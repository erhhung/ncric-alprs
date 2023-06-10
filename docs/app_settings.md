# App Settings

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
                      "https://api.dev.astrometrics.us/datastore/data/set/?setId=6d17e1c0-d61b-4ec8-80ce-1e82b4a64166" \
            | jq
__SEE_PAYLOAD_SECTION__
EOF

# verify app settings stored properly
# (there must be exactly one entity!)
curl -s -H "Authorization: Bearer $jwt" \
        http://datastore:8080/datastore/data/set/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166 \
  | jq

# ensure 70 entity sets are referenced
curl -s -H "Authorization: Bearer $jwt" \
        http://datastore:8080/datastore/data/set/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166 \
  | jq '.[0]."ol.appdetails"[0] | fromjson | .AGENCY_VEHICLE_RECORDS_ENTITY_SETS | keys | length'

# API request issued from the frontend
curl -s -H "Authorization: Bearer $jwt" \
        -H "Content-Type: application/json" \
        -d '{"start":0,"maxHits":1,"searchTerm":"*"}' \
        http://datastore:8080/datastore/search/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166 \
  | jq

# trigger indexing if no hits were found
psql postgresql://alprs_user:SECRET@postgresql:5432/alprs
alprs=> UPDATE ids SET last_index = '-infinity' WHERE entity_set_id = '6d17e1c0-d61b-4ec8-80ce-1e82b4a64166';
```

## Delete & Redo

To delete existing entities from the `6d17e1c0-d61b-4ec8-80ce-1e82b4a64166`
(`app.settings`) entity set, invoke the following APIs:

1. Get entities:

  ```text
  GET https://api.dev.astrometrics.us/datastore/data/set/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166
  ```

2. Delete entities:

  ```text
  # delete ALL entities in an entity set
  DELETE https://api.dev.astrometrics.us/datastore/data/set/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166/all?type=Hard

  # delete specific entities in an entity set
  DELETE https://api.dev.astrometrics.us/datastore/data/set/6d17e1c0-d61b-4ec8-80ce-1e82b4a64166?type=Hard
  ["00000000-0000-0000-8000-0000000000dc", ...]
  ```

## Payload

_**NOTE**: These app settings are already reflected in the PostgreSQL init script "`alprs.sql`"._

_However, **the entity set IDs on dev and prod environments have now diverged** because
we can no longer afford to repopulate the prod database from scratch on each update.  
This means that the `entitySets` object must be recreated from the following SQL query
**in each environment**._

```sql
SELECT CONCAT(' "', id, '": "', title, '",') FROM entity_sets WHERE name LIKE 'NCRICVehicleRecords%' ORDER BY title;
```

_Run the below code snippet from Node.js:_

```js
/*
 * These entity set IDs are environment-specific!
 */
const entitySets = {
  "8356cf75-7dec-4c7c-a854-ba49c284ff92": "Alameda County SO",
  "c6f1e371-0676-49bf-bc15-5531760e26aa": "Anderson City PD",
  "70541b98-92bd-41b8-929e-e9ba1f1a181c": "Atherton PD",
  "1afb2eb8-f702-4117-9706-e499a7116879": "Bay Area Rapid Transit",
  "80eec82e-f5be-4961-bf6f-40be52dd0663": "Benicia PD",
  "4919356f-ec8a-4342-9ad0-c5b11785735c": "Beverly Hills PD",
  "5cbec5cc-21cd-4f0d-8140-2e73842ef45a": "Brisbane PD",
  "87c4fc77-3727-487f-8df7-30cf8decf044": "CHP",
  "1dffd9f3-2e5c-43d0-89a0-c2f9b024a7dc": "Campbell PD",
  "25d0f1aa-12a6-40da-96f2-025f3f17afae": "Central Marin PA",
  "a3693239-25ce-4cc6-a6ea-6b09ae198fff": "Ceres PD",
  "89eab7b8-2ca3-48ed-92f4-9abb693e7fa5": "Chico PD",
  "3a32741b-7e11-4aee-8922-7a10de4bf2f9": "Colma PD",
  "cb3320d3-ec60-4bbb-959d-61d4f45af8fb": "Daly City PD",
  "1d60f7d5-9407-4da4-8a18-a730e4d42569": "Danville PD",
  "48596954-10b5-418e-aa93-0a3e4aa52a60": "Dixon PD",
  "042fb866-b8a3-4b16-a1f1-0a03497329d4": "Fairfield PD",
  "e87a1d0e-555a-462c-a6ae-f43ddf0d969f": "Fremont PD",
  "46b5b4ba-3968-4c56-b063-d4a7c124ffca": "GGB Vista Point",
  "300c24a1-cb7c-4ece-b0bb-1b89c8e05d86": "Gilroy PD",
  "96e8c0a1-92c0-41ff-a894-8760f13d1d93": "HIDTA",
  "ca44aa0e-f0a7-45a7-99d0-ba512651195d": "HPD",
  "2614db49-26a9-4f63-90b9-bcab864598fa": "Hayward PD",
  "351e85a6-9801-42f6-a793-a05d28f42545": "Hercules PD",
  "1179732f-d970-423b-8a4e-f1f23975b133": "Hillsborough PD",
  "209a7814-1457-466c-8bb8-aad5f8c178d7": "Humboldt County",
  "719c4157-9acb-4947-a134-4d38bc409aff": "Kaiser Permanente",
  "5ca42a42-ba66-421f-81bc-cff709d69a6f": "Livermore PD",
  "9bb11a00-8cc8-4eaa-927b-6f95d7b7d603": "Los Altos PD",
  "f0ce392d-8076-4fb9-b7f6-a6f77fb3f3a7": "Manual Entries",
  "99bf2b2a-ea9c-46e6-b800-021db048d060": "Marin CC",
  "358d3835-ecd2-41e2-9f5b-eb7bb65c0dca": "Menlo Park PD",
  "348310d5-a5bc-42df-b3b8-3aeafe20f12a": "Millbrae PD",
  "32b04098-e944-4d1f-b98c-af8ae9fe33ce": "Modesto PD",
  "9d1f6b6a-2bf4-4ee4-84b4-9ac403037ff7": "Morgan Hill PD",
  "7e8ac6a0-b8e1-4220-90ea-8de944fc57e9": "NCRIC",
  "f6f04cc9-7bd0-44c8-bc95-377c4b6d6460": "NPD",
  "3c78b3cb-79c9-49b1-acb5-ffbd70ae84e3": "Napa PD",
  "326e7719-22f0-4fdd-a2b0-0c52cd7e2b84": "Newark PD",
  "96baf6fb-245e-4e90-b517-59f880186556": "Novato PD",
  "57002856-c817-4f5c-a93e-ffddc7825790": "Oakley PD",
  "c0e2f735-4c57-4f58-bd36-916ce4db3abc": "Orinda PD",
  "6fe674a2-143d-4008-ab34-622e6a9aa307": "Palo Alto PD",
  "5c7bf4e7-ea87-46b2-9400-ce0ff444a4a5": "Piedmont PD",
  "a996e1c2-bfd7-4fce-a720-9b9038cae495": "Pleasanton PD",
  "4d97e8f7-5ee9-41e9-9645-eecdda525e38": "Rio Vista PD",
  "ee1337df-7b3b-4fd0-bbbe-27aeb0fc9623": "Rocklin PD",
  "5b043ae9-4d28-46e1-a1cb-671db1f0bf41": "SFO Airport Police",
  "9cff2082-cc92-46e7-a1e7-dd33c32ba99b": "Salinas PD",
  "3c64e25e-0e28-4ce0-ad8b-212d0b2f4712": "San Bruno PD",
  "a52c8aa0-f75a-4698-be2b-d91cf0de65ba": "San Francisco PD",
  "7b36e25a-5df6-4336-9317-80df8a940270": "San Joaquin County SO",
  "80b610af-4448-4bb1-a002-3b900560b4e0": "San Leandro PD",
  "0e4f95e2-e5cb-4f1a-a849-201220e6d174": "San Mateo County SO",
  "8a8761d6-9538-4210-a10a-ca13dbd26f07": "San Mateo PD",
  "edb20fcb-a5bd-4574-9a0c-10be5dc9c589": "San Mateo VTTF",
  "13feca9b-f0ec-4d8c-a92d-6b19e115e81d": "San Ramon PD",
  "c61b4335-13cd-44c0-a605-b0b179fd46ba": "Santa Clara County SO",
  "a1b8796f-0b7e-49ae-9e0d-6a3d7f0e5988": "Santa Clara PD",
  "082d4b06-5bea-474b-937b-d025f150cfae": "Santa Clara Sheriff",
  "595c88d8-0f09-4760-b7ca-01f89e17561f": "Shasta County SO",
  "b4702991-23dd-4b79-9e75-0137c1ca18c4": "Solano County SO",
  "a35a4401-9b1f-4d54-b4b6-d7c062312857": "South San Francisco PD",
  "737c3fd5-65e8-4b90-8bd7-cdd3bccc1565": "Suisun PD",
  "4452d85e-0905-43a2-9053-5dbccc80b838": "Sunnyvale DPS",
  "e229b576-f040-4ff6-85f3-cf317cb64fe7": "Sunnyvale PD",
  "05fcf2e4-cf4d-4033-9073-47ebdbe769db": "V5Sys",
  "1a76efe7-f45f-4160-9f03-aa5d08134d6f": "Vacaville PD",
  "974f5d30-6115-482d-854b-cca289250160": "Vallejo PD",
  "74eeef7a-3e7f-49c3-9c94-365943564cc2": "Yosemite National Park",
};
assert(Object.keys(entitySets).length == 70);

const settings = {
  "AGENCY_VEHICLE_RECORDS_ENTITY_SETS": entitySets,
};
const payload = [{  // this ol.appdetails property type ID is stable
  "6f1cf64a-0bac-47d3-a74d-289b6df50a1b": [JSON.stringify(settings)],
}];
console.log(JSON.stringify(payload, undefined, 2));
```

```json
[
  {
    "6f1cf64a-0bac-47d3-a74d-289b6df50a1b": [
      "{\"AGENCY_VEHICLE_RECORDS_ENTITY_SETS\":{\"8356cf75-7dec-4c7c-a854-ba49c284ff92\":\"Alameda County SO\",\"c6f1e371-0676-49bf-bc15-5531760e26aa\":\"Anderson City PD\",\"70541b98-92bd-41b8-929e-e9ba1f1a181c\":\"Atherton PD\",\"1afb2eb8-f702-4117-9706-e499a7116879\":\"Bay Area Rapid Transit\",\"80eec82e-f5be-4961-bf6f-40be52dd0663\":\"Benicia PD\",\"4919356f-ec8a-4342-9ad0-c5b11785735c\":\"Beverly Hills PD\",\"5cbec5cc-21cd-4f0d-8140-2e73842ef45a\":\"Brisbane PD\",\"87c4fc77-3727-487f-8df7-30cf8decf044\":\"CHP\",\"1dffd9f3-2e5c-43d0-89a0-c2f9b024a7dc\":\"Campbell PD\",\"25d0f1aa-12a6-40da-96f2-025f3f17afae\":\"Central Marin PA\",\"a3693239-25ce-4cc6-a6ea-6b09ae198fff\":\"Ceres PD\",\"89eab7b8-2ca3-48ed-92f4-9abb693e7fa5\":\"Chico PD\",\"3a32741b-7e11-4aee-8922-7a10de4bf2f9\":\"Colma PD\",\"cb3320d3-ec60-4bbb-959d-61d4f45af8fb\":\"Daly City PD\",\"1d60f7d5-9407-4da4-8a18-a730e4d42569\":\"Danville PD\",\"48596954-10b5-418e-aa93-0a3e4aa52a60\":\"Dixon PD\",\"042fb866-b8a3-4b16-a1f1-0a03497329d4\":\"Fairfield PD\",\"e87a1d0e-555a-462c-a6ae-f43ddf0d969f\":\"Fremont PD\",\"46b5b4ba-3968-4c56-b063-d4a7c124ffca\":\"GGB Vista Point\",\"300c24a1-cb7c-4ece-b0bb-1b89c8e05d86\":\"Gilroy PD\",\"96e8c0a1-92c0-41ff-a894-8760f13d1d93\":\"HIDTA\",\"ca44aa0e-f0a7-45a7-99d0-ba512651195d\":\"HPD\",\"2614db49-26a9-4f63-90b9-bcab864598fa\":\"Hayward PD\",\"351e85a6-9801-42f6-a793-a05d28f42545\":\"Hercules PD\",\"1179732f-d970-423b-8a4e-f1f23975b133\":\"Hillsborough PD\",\"209a7814-1457-466c-8bb8-aad5f8c178d7\":\"Humboldt County\",\"719c4157-9acb-4947-a134-4d38bc409aff\":\"Kaiser Permanente\",\"5ca42a42-ba66-421f-81bc-cff709d69a6f\":\"Livermore PD\",\"9bb11a00-8cc8-4eaa-927b-6f95d7b7d603\":\"Los Altos PD\",\"f0ce392d-8076-4fb9-b7f6-a6f77fb3f3a7\":\"Manual Entries\",\"99bf2b2a-ea9c-46e6-b800-021db048d060\":\"Marin CC\",\"358d3835-ecd2-41e2-9f5b-eb7bb65c0dca\":\"Menlo Park PD\",\"348310d5-a5bc-42df-b3b8-3aeafe20f12a\":\"Millbrae PD\",\"32b04098-e944-4d1f-b98c-af8ae9fe33ce\":\"Modesto PD\",\"9d1f6b6a-2bf4-4ee4-84b4-9ac403037ff7\":\"Morgan Hill PD\",\"7e8ac6a0-b8e1-4220-90ea-8de944fc57e9\":\"NCRIC\",\"f6f04cc9-7bd0-44c8-bc95-377c4b6d6460\":\"NPD\",\"3c78b3cb-79c9-49b1-acb5-ffbd70ae84e3\":\"Napa PD\",\"326e7719-22f0-4fdd-a2b0-0c52cd7e2b84\":\"Newark PD\",\"96baf6fb-245e-4e90-b517-59f880186556\":\"Novato PD\",\"57002856-c817-4f5c-a93e-ffddc7825790\":\"Oakley PD\",\"c0e2f735-4c57-4f58-bd36-916ce4db3abc\":\"Orinda PD\",\"6fe674a2-143d-4008-ab34-622e6a9aa307\":\"Palo Alto PD\",\"5c7bf4e7-ea87-46b2-9400-ce0ff444a4a5\":\"Piedmont PD\",\"a996e1c2-bfd7-4fce-a720-9b9038cae495\":\"Pleasanton PD\",\"4d97e8f7-5ee9-41e9-9645-eecdda525e38\":\"Rio Vista PD\",\"ee1337df-7b3b-4fd0-bbbe-27aeb0fc9623\":\"Rocklin PD\",\"5b043ae9-4d28-46e1-a1cb-671db1f0bf41\":\"SFO Airport Police\",\"9cff2082-cc92-46e7-a1e7-dd33c32ba99b\":\"Salinas PD\",\"3c64e25e-0e28-4ce0-ad8b-212d0b2f4712\":\"San Bruno PD\",\"a52c8aa0-f75a-4698-be2b-d91cf0de65ba\":\"San Francisco PD\",\"7b36e25a-5df6-4336-9317-80df8a940270\":\"San Joaquin County SO\",\"80b610af-4448-4bb1-a002-3b900560b4e0\":\"San Leandro PD\",\"0e4f95e2-e5cb-4f1a-a849-201220e6d174\":\"San Mateo County SO\",\"8a8761d6-9538-4210-a10a-ca13dbd26f07\":\"San Mateo PD\",\"edb20fcb-a5bd-4574-9a0c-10be5dc9c589\":\"San Mateo VTTF\",\"13feca9b-f0ec-4d8c-a92d-6b19e115e81d\":\"San Ramon PD\",\"c61b4335-13cd-44c0-a605-b0b179fd46ba\":\"Santa Clara County SO\",\"a1b8796f-0b7e-49ae-9e0d-6a3d7f0e5988\":\"Santa Clara PD\",\"082d4b06-5bea-474b-937b-d025f150cfae\":\"Santa Clara Sheriff\",\"595c88d8-0f09-4760-b7ca-01f89e17561f\":\"Shasta County SO\",\"b4702991-23dd-4b79-9e75-0137c1ca18c4\":\"Solano County SO\",\"a35a4401-9b1f-4d54-b4b6-d7c062312857\":\"South San Francisco PD\",\"737c3fd5-65e8-4b90-8bd7-cdd3bccc1565\":\"Suisun PD\",\"4452d85e-0905-43a2-9053-5dbccc80b838\":\"Sunnyvale DPS\",\"e229b576-f040-4ff6-85f3-cf317cb64fe7\":\"Sunnyvale PD\",\"05fcf2e4-cf4d-4033-9073-47ebdbe769db\":\"V5Sys\",\"1a76efe7-f45f-4160-9f03-aa5d08134d6f\":\"Vacaville PD\",\"974f5d30-6115-482d-854b-cca289250160\":\"Vallejo PD\",\"74eeef7a-3e7f-49c3-9c94-365943564cc2\":\"Yosemite National Park\"}}"
    ]
  }
]
```
