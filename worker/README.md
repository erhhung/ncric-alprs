# Worker Notes

## IMPORTANT

* Do NOT change hardcoded strings "`http://datastore:8080`"
  (often as the default value of the `base_url` function argument)
  anywhere within the `olpy` and `pyntegrationsncric` directories
  because they may be replaced automatically with the proper API
  endpoint (for dev or prod environments) by the `mkwhl.sh` script.
* Do NOT change hardcoded strings "`us-gov-west-1`" (boto3 Session
  `region_name` parameter) as they will also be replaced with the
  appropriate region by the `mkwhl.sh` script.

## pyntegrationsncric

### NCRIC Flights

Generate missing NCRIC flight and images flight YAML files:

_**Run in "`pyntegrationsncric/pyntegrationsncric/pyntegrations/ca_ncric/ncric_flights`"**)_:

```bash
# npm i -g csvtojson

while read es_id; do
  file="ncric_${es_id}_flight.yaml"
  if [ -f "$file" ]; then
    echo >&2 "$file exists."
  else
    cat <<EOF > $file
organizationId: 1446ff84-7112-42ec-828d-f181f45e4d20

entityDefinitions:
  vehiclerecords:
    fqn: "ol.vehicle"
    entitySetName: "NCRICVehicleRecords${es_id}"
    propertyDefinitions:
      ol.id:
        type: "ol.id"
        column: "vehicle_record_id"
      vehicle.licensenumber:
        type: "vehicle.licensenumber"
        column: "VehicleLicensePlateID"
      ol.datelogged:
        type: "ol.datelogged"
        column: "eventDateTime"
      ol.locationcoordinates:
        type: "ol.locationcoordinates"
        column: "latlon"
      publicsafety.agencyname:
        type: "publicsafety.agencyname"
        column: "standardized_agency_name"
      ol.agencyname:
        type: "ol.agencyname"
        column: "agencyName"
      vehicle.model:
        type: "vehicle.model"
        column: "model"
      ol.resourceid:
        type: "ol.resourceid"
        column: "camera_id"
      ol.datasource:
        type: "ol.datasource"
        column: "datasource"
    name: "vehiclerecords"

  imagesources:
    fqn: "ol.imagesource"
    entitySetName: "NCRICImageSources"
    propertyDefinitions:
      ol.id:
        type: "ol.id"
        column: "camera_id"
    name: "imagesources"
    associateOnly: true

  agencies:
    fqn: "ol.agency"
    entitySetName: "NCRICAgencies"
    propertyDefinitions:
      ol.id:
        type: "ol.id"
        column: "agency_id"
    name: "agencies"
    associateOnly: true

  agencies2:
    fqn: "ol.agency"
    entitySetName: "NCRICStandardizedAgencies"
    propertyDefinitions:
      ol.id:
        type: "ol.id"
        column: "standardized_agency_name"
    name: "agencies2"
    associateOnly: true

associationDefinitions:
  recordedby1:
    fqn: "ol.recordedby"
    entitySetName: "NCRICRecordedBy"
    src: "vehiclerecords"
    dst: "imagesources"
    propertyDefinitions:
      ol.datelogged:
        type: "ol.datelogged"
        column: "eventDateTime"
      general.stringid:
        type: "general.stringid"
        column: "recordedby1_id"
    name: "recordedby1"

  recordedby2:
    fqn: "ol.recordedby"
    entitySetName: "NCRICRecordedBy"
    src: "vehiclerecords"
    dst: "agencies"
    propertyDefinitions:
      ol.datelogged:
        type: "ol.datelogged"
        column: "eventDateTime"
      general.stringid:
        type: "general.stringid"
        column: "recordedby2_id"
    name: "recordedby2"

  recordedby3:
    fqn: "ol.recordedby"
    entitySetName: "NCRICRecordedBy"
    src: "vehiclerecords"
    dst: "agencies2"
    propertyDefinitions:
      ol.datelogged:
        type: "ol.datelogged"
        column: "eventDateTime"
      general.stringid:
        type: "general.stringid"
        column: "recordedby3_id"
    name: "recordedby3"

  collectedby:
    fqn: "ol.collectedby"
    entitySetName: "NCRICCollectedBy"
    src: "imagesources"
    dst: "agencies"
    propertyDefinitions:
      general.id:
        type: "general.id"
        column: "collectedby_id"
    name: "collectedby"

  collectedby2:
    fqn: "ol.collectedby"
    entitySetName: "NCRICCollectedBy"
    src: "imagesources"
    dst: "agencies2"
    propertyDefinitions:
      general.id:
        type: "general.id"
        column: "collectedby2_id"
    name: "collectedby2"
EOF
    echo "Created $file"
  fi
done < <(
  csvtojson ../../../../../../docs/standardized_agency_names.csv | \
    jq -r '[.[].standardized_agency_name] | unique[] | "\(gsub(" ";""))"'
)
```

_**Run in "`pyntegrationsncric/pyntegrationsncric/pyntegrations/ca_ncric/ncric_image_flights`"**)_:

```bash
# npm i -g csvtojson

while read es_id; do
  file="ncric_${es_id}_images_flight.yaml"
  if [ -f "$file" ]; then
    echo >&2 "$file exists."
  else
    cat <<EOF > $file
organizationId: 1446ff84-7112-42ec-828d-f181f45e4d20

entityDefinitions:
  vehiclerecords:
    fqn: "ol.vehicle"
    entitySetName: "NCRICVehicleRecords${es_id}"
    propertyDefinitions:
      ol.id:
        type: "ol.id"
        column: "vehicle_record_id"
      ol.licenseplateimage:
        type: "ol.licenseplateimage"
        column: "LPRVehiclePlatePhoto"
      ol.vehicleimage:
        type: "ol.vehicleimage"
        column: "LPRAdditionalPhoto"
    name: "vehiclerecords"

associationDefinitions: {}
EOF
    echo "Created $file"
  fi
done < <(
  csvtojson ../../../../../../docs/standardized_agency_names.csv | \
    jq -r '[.[].standardized_agency_name] | unique[] | "\(gsub(" ";""))"'
)
```

## Update Packages

To update `olpy` and `pyntegrationsncric` packages on the Worker
after Terraform apply, run the following via SSH:

```bash
(
cd ~/packages
eval $(egrep "(S3_URL)=\"" /bootstrap.sh | awk '{print $2}')
aws s3 sync $S3_URL/worker . --exclude '*' --include '*.whl' --no-progress

for wheel in pyntegrationsncric olpy; do
  whl=$(unzip -l $wheel.whl | sed -En "s|.+($wheel-[0-9.]+)\.dist-info/WHEEL|\1-py3-none-any.whl|p")
  mv -f $wheel.whl $whl && pip3 install --force-reinstall $whl
done
)
```

## Useful Queries

_Enter the `pgcli` prompt by running either `alprs` or `atlas`
(Bash functions defined in "`~/.bash_aliases`"), depending on
which database you'd like to connect to._

Show number of Flock reads per day:

```sql
SELECT DISTINCT(timestamp::date) AS date,
  COUNT(*) OVER (PARTITION BY timestamp::date) AS count
FROM (
  SELECT timestamp FROM integrations.flock_reads_sun UNION
  SELECT timestamp FROM integrations.flock_reads_mon UNION
  SELECT timestamp FROM integrations.flock_reads_tue UNION
  SELECT timestamp FROM integrations.flock_reads_wed UNION
  SELECT timestamp FROM integrations.flock_reads_thu UNION
  SELECT timestamp FROM integrations.flock_reads_fri UNION
  SELECT timestamp FROM integrations.flock_reads_sat) AS _table
ORDER BY timestamp::date;
```

Show number of Flock reads (total and top 3 cameras) per agency:

```sql
WITH q1 AS
(
  SELECT *
    -- crosstab() requires "tablefunc" extension
    FROM crosstab(
      $$
      WITH q1 AS
      (
        SELECT agency, num_reads::INT,
               RANK() OVER (PARTITION BY agency
                                ORDER BY num_reads DESC
                           ) AS top_n
          FROM (
               SELECT DISTINCT(standardized_agency_name) AS agency,
                      COUNT(*)                           AS num_reads
                 FROM flock_reads_tue
            LEFT JOIN standardized_agency_names
                   ON "ol.name"       = cameranetworkname
                  AND "ol.datasource" = 'FLOCK'
             GROUP BY DISTINCT(standardized_agency_name), cameraname
          ) AS q2
      )
        SELECT agency, top_n, num_reads
          FROM q1
         WHERE top_n <= 3
      ORDER BY agency, top_n
      $$
    ) AS ct (agency TEXT, reads1 INT, reads2 INT, reads3 INT)
),
q2 AS
(
     SELECT DISTINCT(standardized_agency_name) AS agency,
            COUNT(DISTINCT(cameraid))          AS num_cams,
            COUNT(*)                           AS num_reads
       FROM flock_reads_tue
  LEFT JOIN standardized_agency_names
         ON "ol.name"       = cameranetworkname
        AND "ol.datasource" = 'FLOCK'
   GROUP BY DISTINCT(standardized_agency_name)
)
    SELECT q1.agency,
           q2.num_cams  AS num_cameras,
           q2.num_reads AS tot_reads,
           q1.reads1    AS top1_reads,
           q1.reads2    AS top2_reads,
           q1.reads3    AS top3_reads
      FROM q1
INNER JOIN q2
        ON q1.agency = q2.agency
  ORDER BY q1.agency;
```

Show number of Flock reads and last timestamp per agency in a day table:

```sql

SELECT                     DISTINCT(cameranetworkname) AS agency,
  COUNT(*)       OVER (PARTITION BY cameranetworkname) AS reads,
                                          daily_limit  AS allowed,
  MAX(timestamp) OVER (PARTITION BY cameranetworkname) AS last_time
FROM flock_reads_thu
INNER JOIN network ON cameranetworkname = name
ORDER BY last_time;
```
