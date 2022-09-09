from pyntegrationsncric.pyntegrations.ca_ncric.utils.integration_base_classes import Integration
from pyntegrationsncric.pyntegrations.ca_ncric.alpr_cleaning.integration_definitions_s3 import \
    ALPRIntegration, ALPRImagesIntegration, ALPRImageSourcesIntegration, ALPRAgenciesIntegration
from pkg_resources import resource_filename
import pandas as pd

# calling from ncric_cleaning module since BOSS3 and SCSO have similar data structures


class SCSOIntegration(ALPRIntegration):
    def __init__(
        self,
        raw_table_name="scso_hourly_clean",
        raw_table_name_images="scso_images_hourly_raw",
        s3_bucket="sftp.openlattice.com",
        s3_prefix="ncricscso",
        limit=None,
        date_start=None,
        date_end=None,
        col_list=None
    ):
        super().__init__(
            s3_bucket=s3_bucket,
            s3_prefix=s3_prefix,
            limit=limit,
            date_start=date_start,
            date_end=date_end,
            raw_table_name=raw_table_name,
            raw_table_name_images=raw_table_name_images,
            datasource="SCSO",
            col_list=col_list
        )


class SCSOImagesIntegration(Integration):
    def __init__(
        self,
        sql="select * from scso_images_hourly_raw",
        clean_table_name_root="scso_images_hourly_clean",
        flight_name="ncric_scso_images_flight.yaml",
        base_url="http://datastore:8080",
        clean_table_suffix=None
    ):
        super().__init__(
            sql=sql,
            clean_table_name_root="_".join(filter(None, [clean_table_name_root, clean_table_suffix])),
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url
        )

    def clean_row(cls, row):
        return ALPRImagesIntegration.clean_row(cls, row, "SCSO")


class SCSOImageSourcesIntegration(Integration):
    def __init__(
        self,
        sql,
        base_url="http://datastore:8080",
        clean_table_name_root="zzz_clean_scso_imagesources",
        flight_name="ncric_scso_imagesources_flight.yaml"
    ):
        super().__init__(
            sql=sql,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url
        )

    def clean_row(cls, row):
        return ALPRImageSourcesIntegration.clean_row(cls, row)


class SCSOAgenciesIntegration(Integration):
    def __init__(
        self,
        sql,
        base_url="http://datastore:8080",
        clean_table_name_root="zzz_clean_scso_agencies",
        flight_name="ncric_scso_agencies_flight.yaml"
    ):
        super().__init__(
            sql=sql,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url
        )

    def clean_row(cls, row):
        return ALPRAgenciesIntegration.clean_row(cls, row)


class SCSOAgenciesStandardizedIntegration(Integration):
    def __init__(
        self,
        sql="""select distinct standardized_agency_name from standardized_agency_names where "ol.datasource" = 'SCSO';""",
        base_url="http://datastore:8080",
        clean_table_name_root="zzz_clean_scso_agencies_standardized",
        flight_name="ncric_scso_agencies_standardized.yaml"
    ):
        super().__init__(
            sql=sql,
            clean_table_name_root="zzz_clean_scso_agency_standardization",
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url)


class SCSOGeoFix(Integration):
    def __init__(self, sql="""select * from scso_geo_fix;"""):
        super().__init__(
            sql=sql,
            clean_table_name_root="zzz_clean_scso_geofix",
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, "ncric_scso_dt_geo_fix.yaml"),
            base_url="http://datastore:8080")


class SCSOHotlistDaily(Integration):
    def __init__(
        self,
        sql="""select hotlist_daily.*, scso_hourly.* from hotlist_daily
                inner join scso_hourly_clean on "plate" = "VehicleLicensePlateID";
                """,
        base_url="http://datastore:8080",
        clean_table_name_root="zzz_clean_scso_hotlist_hourly",
        flight_name="ncric_scso_hotlist_flight.yaml"
    ):
        super().__init__(
            sql=sql,
            clean_table_name_root=clean_table_name_root,
            standardize_clean_table_name=False,
            if_exists="replace",
            flight_path=resource_filename(__name__, flight_name),
            base_url=base_url)
