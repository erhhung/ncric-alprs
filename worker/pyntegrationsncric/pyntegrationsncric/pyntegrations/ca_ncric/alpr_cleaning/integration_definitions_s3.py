from pyntegrationsncric.pyntegrations.ca_ncric.utils.integration_base_classes import Integration
from datetime import datetime, timedelta
import base64
import boto3
import json
import pandas as pd
import pytz
import sqlalchemy
import os

db_user = os.environ.get("RD_OPTION_DB_USER")
db_pass = os.environ.get("RD_OPTION_DB_PASS")
db_host = os.environ.get("RD_OPTION_DB_HOST")
db_name = os.environ.get("RD_OPTION_DB_NAME")

class ALPRIntegration(Integration):
    def __init__(
        self,
        raw_table_name,
        raw_table_name_images,
        datasource,
        s3_bucket,
        s3_prefix,
        limit=None,
        date_start=None,
        date_end=None,
        atlas_organization_id="1446ff84-7112-42ec-828d-f181f45e4d20",
        standardized_agency_table="standardized_agency_names",
        col_list=None
    ):

        super().__init__(
            if_exists="replace",
            base_url="https://api.dev.astrometrics.us",
            atlas_organization_id=atlas_organization_id)

        self.s3_bucket = s3_bucket
        self.s3_prefix = s3_prefix
        self.limit = limit
        self.raw_table_name = raw_table_name
        self.raw_table_name_images = raw_table_name_images
        self.datasource = datasource
        self.standardized_agency_table = standardized_agency_table
        self.col_list = col_list

        self.image_cols = ["LPREventID", "standardized_agency_name",
                           "VehicleLicensePlateID", "LPRVehiclePlatePhoto", "LPRAdditionalPhoto"]
        utc = pytz.UTC

        if date_start is not None:
            try:
                self.date_start = utc.localize(datetime.strptime(date_start, "%Y-%m-%d %H:%M:%S"))
            except:
                raise ValueError("Date start should be in string datetime format of %Y-%m-%d %H:%M:%S!")
        else:
            self.date_start = None
        if date_end is not None:
            try:
                self.date_end = utc.localize(datetime.strptime(date_end, "%Y-%m-%d %H:%M:%S"))
            except:
                raise ValueError("Date end should be in string datetime format of %Y-%m-%d %H:%M:%S!")
        else:
            self.date_end = None

        if bool(date_start) != bool(date_end):
            raise ValueError(
                "Need to have both date start and date end specified! Otherwise don't specify and run everything.")

        if date_start is not None and date_end is not None and self.date_start >= self.date_end:
            raise ValueError("Date start should be earlier than date end!")

    def join_string(self, ls):
        s = "_".join(ls)
        if s == "":
            return None
        else:
            return s

    def convert_latlon(self, degrees, minutes, seconds):
        if degrees < 0:
            return float(degrees) - float(minutes) / 60 - float(seconds) / 3600
        else:
            return float(degrees) + float(minutes) / 60 + float(seconds) / 3600

    def clean_row(self, row):
        newdict = {}
        newdict['eventDateTime'] = None
        newdict['latlon'] = None
        newdict['location_id'] = None
        if pd.notnull(row.LatitudeDegreeValue) and pd.notnull(row.LongitudeDegreeValue):
            latitude = self.convert_latlon(row.LatitudeDegreeValue, row.LatitudeMinuteValue, row.LatitudeSecondValue)
            latitude = str(latitude)
            longitude = self.convert_latlon(row.LongitudeDegreeValue,
                                            row.LongitudeMinuteValue, row.LongitudeSecondValue)
            longitude = str(longitude)
            newdict['latlon'] = ",".join([latitude, longitude])
            newdict['location_id'] = "-".join([latitude, longitude])
        if pd.notnull(row.eventDate) and pd.notnull(row.eventTime):
            try:
                event_datetime = datetime.strptime(f"{row.eventDate} {row.eventTime}", "%Y-%m-%d %H:%M:%S")
                newdict['eventDateTime'] = pytz.timezone("UTC").localize(event_datetime)
            except ValueError as err:
                print(f"Read data formatted incorrectly as {err}")
                pass

        if pd.notnull(row.LPREventID):
            newdict['vehicle_record_id'] = f"{row.LPREventID}_{self.datasource}"

        newdict['VehicleLicensePlateID'] = row.VehicleLicensePlateID
        newdict['agencyName'] = row.agencyName
        newdict['agencyAcronym'] = row.agencyAcronym
        newdict['datasource'] = self.datasource
        newdict['LPRCameraName'] = row.LPRCameraName
        newdict['standardized_agency_name'] = row.standardized_agency_name

        if self.datasource == "BOSS4":
            datasource = "None"
        else:
            datasource = self.datasource

        newdict['camera_id'] = self.join_string(filter(lambda x: x != "None", [row.LPRCameraID, datasource]))
        newdict['agency_id'] = self.join_string(filter(lambda x: x != "None", [row.agencyOriNumber, datasource]))

        newdict['has_id'] = self.join_string(
            filter(lambda x: x != "None", [str(row.VehicleLicensePlateID), str(row.LPREventID), datasource]))
        newdict['recordedby1_id'] = self.join_string(
            filter(lambda x: x != "None", [str(row.LPREventID), str(row.LPRCameraID), datasource]))
        newdict['recordedby2_id'] = self.join_string(
            filter(lambda x: x != "None", [str(row.LPREventID), str(row.agencyOriNumber), datasource]))
        newdict['recordedby3_id'] = self.join_string(
            filter(lambda x: x != "None", [str(row.LPREventID), str(row.standardized_agency_name), datasource]))
        newdict['collectedby_id'] = self.join_string(
            filter(lambda x: x != "None", [str(row.LPRCameraID), str(row.agencyOriNumber), datasource]))
        newdict['collectedby2_id'] = self.join_string(
            filter(lambda x: x != "None", [str(row.LPRCameraID), str(row.standardized_agency_name), datasource]))
        newdict['locatedat1_id'] = self.join_string(
            filter(lambda x: x != "None" and x is not None, [str(row.LPRCameraID), newdict['location_id'], datasource]))
        newdict['locatedat2_id'] = self.join_string(
            filter(lambda x: x != "None" and x is not None, [str(row.LPREventID), newdict['location_id'], datasource]))
        newdict['locatedat3_id'] = self.join_string(
            filter(lambda x: x != "None" and x is not None, [str(row.VehicleLicensePlateID), newdict['location_id'], datasource]))

        return pd.Series(newdict)

    def get_raw_data_from_s3(self):
        session = boto3.session.Session(region_name="us-west-2")
        s3 = session.resource('s3')
        bucket = s3.Bucket(name=self.s3_bucket)

        if self.s3_prefix is None:
            files = bucket.objects.all()
        else:
            files = bucket.objects.filter(Prefix=self.s3_prefix)

        df = pd.DataFrame()
        used_files = []
        idx = 0
        for obj in files:
            if self.limit is not None and idx >= self.limit:
                break
            extension = obj.key.split(".")[-1]  # get the file extension
            # check that the file extension is correctly JSON
            if extension == "json":
                if self.date_start is not None:
                    # currently structured as ncric/READS_OpenLattice_20201026T223918_20201026T224259_609759672.json
                    # so we can extract date from here
                    date = obj.last_modified
                    if date < self.date_start or date > self.date_end:
                        continue
                file = s3.Object(self.s3_bucket, obj.key)
                try:
                    data = json.loads(file.get()['Body'].read().decode('utf-8'))
                    data = pd.json_normalize(data)
                    df = pd.concat([df, data])
                    idx += 1
                    used_files.append(obj.key)
                except json.decoder.JSONDecodeError as err:
                    # try to parse again if the files cannot be parsed...
                    # can make more robust if needed but for now seems to be a solid workaround
                    # assume that: unterminated string issues occur at the very end of parsing. (This is true of the few samples I received)
                    # also assume that primary issue is unterminated string; all others are seeming to be issues about empty files
                    if "Unterminated string" in str(err):
                        print(f"FILE {obj.key} COULD NOT BE SUCCESSFULLY PARSED due to {err}!!!! Will fix this issue.")
                        data_string = file.get()['Body'].read().decode('utf-8')  # turn from binary to string
                        open_braces_count = data_string.count("{")
                        close_braces_count = data_string.count("}")
                        quotation_count = data_string.count('"')

                        # count the number of braces and quotations, check if there are a supposed number of them,
                        # if not add to the end of the string
                        # this assumes that no data contains any of these characters. Cannot completely verify this at the moment.
                        # if the brace counts are not equal...
                        if open_braces_count != close_braces_count:
                            # if the quotation is not terminated at the end... force a quotation mark.
                            if quotation_count % 2 != 0 and data_string[-1] != '"':
                                data_string += '"'
                            # add the closing values for the string
                            data_string += "\t\n}\n]"
                        # in case the only thing missing is this bracket...
                        if "]" not in data_string:
                            data_string += "]"
                        try:
                            # try extracting data again.
                            data = json.loads(data_string)
                            data = pd.json_normalize(data)
                            df = pd.concat([df, data])
                            idx += 1
                            used_files.append(obj.key)
                        except json.decoder.JSONDecodeError as err:
                            print(f"Could not parse file {file} correctly due to {err}, fix this another time.")
                            pass

                    # only other error occurred once so far; it was an empty file.
                    else:
                        print(f"Could not parse file {file} correctly due to {err}. Check again.")
                    pass

        engine = sqlalchemy.create_engine(
            f"postgresql://{db_user}:{db_pass}@{db_host}:5432/{db_name}")
        # engine = self.flight.get_atlas_engine_for_organization()

        # exit cleanly if there are any issues...
        if len(df.index) == 0:
            print("No data to upload! Creating a new empty table.")
            dtypes = self.flight.get_pandas_datatypes_by_column()
            empty = pd.DataFrame(columns=dtypes.keys())
            empty.to_sql(
                self.raw_table_name,
                engine,
                if_exists='replace',
                dtype=dtypes,
                index=False
            )
            return f"select * from {self.raw_table_name}"

        # filter out any bad dates
        if self.date_end is not None:
            df = df[pd.notnull(df['eventDate'])]
            df['tmp_date'] = pd.to_datetime(df['eventDate'], format="%Y-%m-%d", errors='coerce', utc=True)
            # This means that the data is not significantly later than the expected date
            # This should not be happening.
            # adding a one day buffer, just in case
            # this is to prevent bad datetimes (such as the datetimes that showed 2021-12-31 in 2020)
            df = df[df['tmp_date'] <= self.date_end + timedelta(days=1)]

        df = df[(pd.notnull(df['LPREventID'])) & (df['LPREventID'] != "${read.id}")]

        # grab the standardized agency table and left join
        standardized_agency_table = pd.read_sql(
            f"""select * from {self.standardized_agency_table} where "ol.datasource" = '{self.datasource}';""", engine)
        df = df.merge(standardized_agency_table, left_on="agencyName", right_on="ol.name", how="left")

        add_agency = pd.DataFrame()

        # find all the agencies that are not part of the standardized agency name
        # unfortunately BOSS4 ends up getting a lot of NA values, so we need an extra check to make sure
        # there also exists an agency name - otherwise, I'm getting lots of Nones appended
        agency_names = df[(pd.isnull(df['standardized_agency_name'])) & (pd.notnull(df['agencyName']))][['agencyName']]
        if len(agency_names) > 0:
            # make the standardized agency name the same as the actual agency name (at least temporarily)
            print("Adding new agency!")
            add_agency = agency_names.drop_duplicates()
            add_agency = add_agency.rename({"agencyName": "ol.name"}, axis=1)
            add_agency['standardized_agency_name'] = add_agency['ol.name']
            add_agency['ol.datasource'] = self.datasource
            add_agency = add_agency[['ol.name', 'standardized_agency_name', 'ol.datasource']]

        # check difference between sets and add if sets are different

        with engine.connect() as connection:
            if len(df.index) > 0:
                df.columns = [x.split(".")[-1] for x in df.columns]

                df_img = df[self.image_cols]
                # grab everything in the images list BESIDES standardized agency name and LPREventID
                df_col_list = list(set(df.columns) - set(self.image_cols[3:]))
                df = df[df_col_list]
                df = df.apply(self.clean_row, axis=1)
                # subset columns if we want to upload less columns for catch up jobs
                if self.col_list:
                    df = df[self.col_list]

                # figure out how to drop sql table for daily use
                df.to_sql(
                    self.raw_table_name,
                    connection,
                    if_exists='replace',
                    index=False,
                    # dtype={col: (sqlalchemy.sql.sqltypes.String) for col in df.columns},
                    chunksize=1000,
                    method='multi'
                )

                if self.raw_table_name_images:
                    df_img.to_sql(
                        self.raw_table_name_images,
                        connection,
                        if_exists='replace',
                        index=False,
                        chunksize=1000,
                        dtype={col: (sqlalchemy.sql.sqltypes.String) for col in df.columns},
                        method='multi'
                    )
                    print(f"Uploaded {len(df.index)} rows of data to {self.raw_table_name} and {self.raw_table_name_images}!")
                else:
                    print(f"Uploaded {len(df.index)} rows of data to {self.raw_table_name}!")

                if len(add_agency.index) > 0:
                    add_agency.to_sql(
                        self.standardized_agency_table,
                        connection,
                        if_exists='append',
                        index=False
                    )
                    print(f"Uploaded {len(add_agency.index)} rows to {self.standardized_agency_table}!")

        return self.raw_table_name, self.raw_table_name_images


class ALPRImagesIntegration(Integration):
    '''## For the Hotlist images, we will reuse this class but input "ncric_boss4_hotlistimages_flight.yaml"
   and add a clean table suffix of "hotlist"
   and hotlist sql="select \"LPREventID\", \"LPRVehiclePlatePhoto\", \"LPRAdditionalPhoto\" 
   from hotlist_daily  inner join boss4_hourly on \"plate\" = \"VehicleLicensePlateID\" " \
                                                "inner join boss4_images_hourly using(\"LPREventID\");"
   It's all the same property values, just different entity sets'''
    def clean_row(cls, row, datasource):
        newdict = {}
        if row.LPRVehiclePlatePhoto is not None:
            try:
                encoded = str(row.LPRVehiclePlatePhoto).encode('utf-8')
                newdict['LPRVehiclePlatePhoto'] = base64.decodebytes(encoded)
            except:
                print("Bad plate photo detected...")
                newdict['LPRVehiclePlatePhoto'] = None
                pass
        if row.LPRAdditionalPhoto is not None:
            try:
                encoded = str(row.LPRAdditionalPhoto).encode('utf-8')
                newdict['LPRAdditionalPhoto'] = base64.decodebytes(encoded)
            except:
                print("Bad additional photo detected...")
                newdict['LPRAdditionalPhoto'] = None
                pass
        newdict['vehicle_record_id'] = f"{row.LPREventID}_{datasource}"
        newdict['standardized_agency_name'] = row.standardized_agency_name
        newdict['VehicleLicensePlateID'] = str(row.VehicleLicensePlateID)
        return pd.Series(newdict)


class ALPRImageSourcesIntegration(Integration):
    def clean_row(cls, row):
        newdict = {}
        newdict['camera_id'] = row.camera_id
        newdict['LPRCameraName'] = row.LPRCameraName
        newdict['datasource'] = row.datasource
        return pd.Series(newdict)

# class ALPRVehiclesIntegration(Integration):
#     def clean_row(cls, row):
#         newdict = {}
#         newdict['VehicleLicensePlateID'] = row.VehicleLicensePlateID
#         newdict['datasource'] = row.datasource
#         newdict['standardized_agency_name'] = row.standardized_agency_name
#         return pd.Series(newdict)


class ALPRAgenciesIntegration(Integration):
    def clean_row(cls, row):
        newdict = {}
        newdict['agency_id'] = row.agency_id
        newdict['agencyName'] = row.agencyName
        newdict['datasource'] = row.datasource
        newdict['agencyAcronym'] = row.agencyAcronym
        return pd.Series(newdict)
