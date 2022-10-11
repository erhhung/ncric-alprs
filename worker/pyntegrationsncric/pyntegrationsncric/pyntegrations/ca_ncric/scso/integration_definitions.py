from pyntegrationsncric.pyntegrations.ca_ncric.utils.integration_base_classes import Integration
from pyntegrationsncric.pyntegrations.ca_ncric.alpr_cleaning.integration_definitions_s3 import \
    ALPRIntegration, ALPRImagesIntegration, ALPRImageSourcesIntegration, ALPRAgenciesIntegration
from pkg_resources import resource_filename
from datetime import datetime

# calling from ncric_cleaning module since BOSS3 and SCSO have similar data structures


def timestamp_suffix():
    dt = datetime.now()
    dt_string = "_".join([str(dt.year), str(dt.month), str(
        dt.day), str(dt.hour), str(dt.minute), str(dt.second)])
    return f"_{dt_string}"


class SCSOIntegration(ALPRIntegration):
    def __init__(self,
                 jwt=None,
                 raw_table_name="scso_hourly",
                 raw_table_name_images="scso_images_hourly",
                 use_timestamp_table=True,
                 s3_bucket="alprs-sftp-prod",
                 s3_prefix="scso",
                 limit=None,
                 date_start=None,
                 date_end=None,
                 col_list=None,
                 ):

        if use_timestamp_table:
            table_name_suffix = timestamp_suffix()
            raw_table_name += table_name_suffix
            raw_table_name_images += table_name_suffix

        super().__init__(
            raw_table_name=raw_table_name,
            raw_table_name_images=raw_table_name_images,
            datasource="SCSO",
            s3_bucket=s3_bucket,
            s3_prefix=s3_prefix,
            limit=limit,
            date_start=date_start,
            date_end=date_end,
            col_list=col_list,
            jwt=jwt,
        )


class SCSOImagesIntegration(Integration):
    def __init__(self,
                 jwt=None,
                 sql="SELECT * FROM scso_images_hourly_raw",
                 base_url="http://datastore:8080",
                 flight_name="ncric_scso_images_flight.yaml",
                 clean_table_name_root="scso_hr_images",
                 use_timestamp_table=True,
                 ):

        if use_timestamp_table:
            clean_table_name_root += timestamp_suffix()

        super().__init__(
            jwt=jwt,
            sql=sql,
            atlas_organization_id="1446ff84-7112-42ec-828d-f181f45e4d20",
            base_url=base_url,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
        )

    def clean_row(cls, row):
        return ALPRImagesIntegration.clean_row(cls, row, "SCSO")


class SCSOImageSourcesIntegration(Integration):
    def __init__(self,
                 sql,
                 jwt=None,
                 base_url="http://datastore:8080",
                 flight_name="ncric_scso_imagesources_flight.yaml",
                 clean_table_name_root="scso_imagesources",
                 use_timestamp_table=True,
                 drop_table_on_success=False,
                 ):

        if use_timestamp_table:
            clean_table_name_root += timestamp_suffix()

        super().__init__(
            jwt=jwt,
            sql=sql,
            base_url=base_url,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            drop_table_on_success=drop_table_on_success,
        )

    def clean_row(cls, row):
        return ALPRImageSourcesIntegration.clean_row(cls, row)


class SCSOAgenciesIntegration(Integration):
    def __init__(self,
                 sql,
                 jwt=None,
                 base_url="http://datastore:8080",
                 flight_name="ncric_scso_agencies_flight.yaml",
                 clean_table_name_root="scso_agencies",
                 use_timestamp_table=True,
                 drop_table_on_success=False,
                 ):

        if use_timestamp_table:
            clean_table_name_root += timestamp_suffix()

        super().__init__(
            jwt=jwt,
            sql=sql,
            base_url=base_url,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            drop_table_on_success=drop_table_on_success,
        )

    def clean_row(cls, row):
        return ALPRAgenciesIntegration.clean_row(cls, row)


class SCSOStandardizedAgenciesIntegration(Integration):
    def __init__(self,
                 jwt=None,
                 sql=None,
                 base_url="http://datastore:8080",
                 flight_name="ncric_scso_agencies_standardized.yaml",
                 ):

        if sql is None:
            sql = """
                SELECT DISTINCT standardized_agency_name
                FROM standardized_agency_names
                WHERE "ol.datasource" = 'SCSO'
                """

        super().__init__(
            jwt=jwt,
            sql=sql,
            base_url=base_url,
            standardize_clean_table_name=True,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
        )


class SCSOHotlistDaily(Integration):
    def __init__(self,
                 jwt=None,
                 sql=None,
                 base_url="http://datastore:8080",
                 flight_name="ncric_scso_hotlist_flight.yaml",
                 ):

        if sql is None:
            sql = """
                SELECT hotlist_daily.*, scso_hourly.*
                FROM hotlist_daily
                INNER JOIN scso_hourly_clean ON "plate" = "VehicleLicensePlateID"
                """

        super().__init__(
            jwt=jwt,
            sql=sql,
            base_url=base_url,
            standardize_clean_table_name=True,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
        )
