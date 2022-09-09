from pyntegrationsncric.pyntegrations.ca_ncric.utils.integration_base_classes import Integration
from pyntegrationsncric.pyntegrations.ca_ncric.alpr_cleaning.integration_definitions_s3 import \
    ALPRIntegration, ALPRImagesIntegration, ALPRImageSourcesIntegration, ALPRAgenciesIntegration
from pkg_resources import resource_filename
from datetime import datetime, timedelta
# import pandas as pd
# import base64
# import boto3
# import json

# Can input a different flight than default if needed for bugfixes

# BOSS4 integration
# gets cleaning function from ALPRIntegration; passing in None as datasource
# in order to create IDs


class BOSS4Integration(ALPRIntegration):
    def __init__(self,
                 sql=None,
                 raw_table_name='boss4_hourly_clean',
                 raw_table_name_images='boss4_images_hourly_raw',
                 s3_bucket="alprs-sftp-prod",
                 s3_prefix="boss4",
                 limit=None,
                 date_start=None,
                 date_end=None,
                 col_list=None,
                 add_timestamp_table=True
                 ):

        if add_timestamp_table:
            dt = datetime.now()
            dt_string = "_".join([str(dt.year), str(dt.month), str(
                dt.day), str(dt.hour), str(dt.minute), str(dt.second)])
            raw_table_name = f"{raw_table_name}_{dt_string}"
            raw_table_name_images = f"{raw_table_name_images}_{dt_string}"

        self.raw_table_name = raw_table_name
        self.raw_table_name_images = raw_table_name_images

        super().__init__(
            raw_table_name=raw_table_name,
            raw_table_name_images=raw_table_name_images,
            s3_bucket=s3_bucket,
            s3_prefix=s3_prefix,
            limit=limit,
            date_start=date_start,
            date_end=date_end,
            col_list=col_list,
            datasource="BOSS4"
        )

    def drop_main_table(self):
        try:
            self.engine.execute(f"DROP TABLE {self.raw_table_name};")
            print(f"Dropped table {self.raw_table_name}")
        except Exception as e:
            print(f"Could not drop main table due to {str(e)}")

    def drop_images_table(self):
        try:
            self.engine.execute(f"DROP TABLE {self.raw_table_name_images};")
            print(f"Dropped table {self.raw_table_name_images}")
        except Exception as e:
            print(f"Could not drop images table due to {str(e)}")


class BOSS4ImagesIntegration(Integration):
    def __init__(
        self,
        sql,
        base_url="http://datastore:8080",
        flight_name="ncric_boss4_images_flight.yaml",
        clean_table_name_root="boss4_hr_images",
        standardize_table_name=False,
        clean_table_suffix=None
    ):

        super().__init__(
            sql=sql,
            atlas_organization_id="1446ff84-7112-42ec-828d-f181f45e4d20",
            clean_table_name_root="_".join(filter(None, [clean_table_name_root, clean_table_suffix])),
            standardize_clean_table_name=standardize_table_name,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url
        )

    def clean_row(cls, row):
        return ALPRImagesIntegration.clean_row(cls, row, "BOSS4")


class BOSS4ImageSourcesIntegration(Integration):
    # 'select distinct "LPRCameraID", "LPRCameraName", "datasource" from boss4_hourly'
    # imagesources uses the same flight everywhere, so we can specify here the flight
    def __init__(self, sql, base_url="http://datastore:8080",
                 flight_name="ncric_boss4_imagesources_flight.yaml",
                 clean_table_name_root="boss4_imagesources",
                 drop_table_on_success=False
                 ):
        super().__init__(
            sql=sql,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url,
            drop_table_on_success=drop_table_on_success
        )

    def clean_row(cls, row):
        return ALPRImageSourcesIntegration.clean_row(cls, row)


class BOSS4AgenciesIntegration(Integration):
    # 'select distinct "agency_id", "agencyName", "datasource", "agencyAcronym" from boss4_hourly_clean'
    def __init__(
        self,
        sql,
        base_url="http://datastore:8080",
        clean_table_name_root="boss4_agencies_clean",
        flight_name="ncric_boss4_agencies_flight.yaml",
        drop_table_on_success=False
    ):

        super().__init__(
            sql=sql,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url,
            drop_table_on_success=drop_table_on_success
        )

    def clean_row(cls, row):
        return ALPRAgenciesIntegration.clean_row(cls, row)


class BOSS4AgenciesStandardizedIntegration(Integration):
    def __init__(self,
                 base_url="http://datastore:8080",
                 sql="""select distinct standardized_agency_name from standardized_agency_names where "ol.datasource" = 'BOSS4';""",
                 flight_name="ncric_boss4_agencies_standardized.yaml",
                 drop_table_on_success=False
                 ):
        super().__init__(
            sql=sql,
            standardize_clean_table_name=True,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url,
            drop_table_on_success=drop_table_on_success
        )


class BOSS4HotlistDaily(Integration):
    # """select hotlist_daily.*, boss4_hourly_clean.* from hotlist_daily
    # inner join boss4_hourly on "plate" = "VehicleLicensePlateID";"""
    def __init__(self,
                 sql,
                 base_url="http://datastore:8080",
                 clean_table_name_root="clean_boss4_hotlist_hourly",
                 drop_table_on_success=False
                 ):
        super().__init__(
            sql=sql,
            atlas_organization_id="1446ff84-7112-42ec-828d-f181f45e4d20",
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=True,
            if_exists="replace",
            flight_path=resource_filename(__name__, "ncric_boss4_hotlist_flight.yaml"),
            base_url=base_url,
            drop_table_on_success=drop_table_on_success)
