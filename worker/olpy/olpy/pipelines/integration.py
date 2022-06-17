import olpy
import importlib
import pandas as pd
import uuid
import yaml
import re
import subprocess
import sqlalchemy
import os
from urllib.parse import unquote
from pkg_resources import resource_filename
import traceback


class Integration(object):
    """
    A class representing an integration configuration
    """

    def __init__(self,
                 integration_config=None,
                 sql=None,
                 csv=None,
                 clean_table_name_root="tmp",
                 standardize_clean_table_name=True,
                 if_exists="fail",
                 flight_path=None,
                 atlas_organization_id=None,
                 base_url="https://api.openlattice.com",
                 rowwise=None,
                 cleaning_required=True,
                 shuttle_path=None,
                 drop_table_on_success=False,
                 jwt=None,
                 org_engine=True):

        # load integration definition
        local_config = dict()
        if isinstance(integration_config, str):
            with open(integration_config, "r") as cf:
                local_config = yaml.load(cf.read(), Loader=yaml.FullLoader)
        elif isinstance(integration_config, dict):
            local_config = integration_config
        elif integration_config is not None:
            raise ValueError("The provided integration_config is not a yaml path or dictionary.")

        self.__dict__.update(local_config)

        with open(resource_filename(__name__, "pipeline_config.yaml"), "r") as gcf:
            global_config = yaml.load(gcf.read(), Loader=yaml.FullLoader)

            # local config supercedes global wherever it overlaps

            for k, v in global_config.items():
                if not k in self.__dict__.keys() or not self.__dict__[k]:
                    self.__dict__[k] = v

        if "sql" in self.__dict__:
            if sql:
                raise ValueError("SQL query specified twice.")
        else:
            self.sql = sql
        if "csv" in self.__dict__:
            if csv:
                raise ValueError("CSV path specified twice.")
        else:
            self.csv = csv

        if "clean_table_name_root" not in self.__dict__:
            self.clean_table_name_root = clean_table_name_root
        if "standardize_clean_table_name" not in self.__dict__:
            self.standardize_clean_table_name = standardize_clean_table_name
        if "if_exists" not in self.__dict__:
            self.if_exists = if_exists
        if "flight_path" not in self.__dict__:
            self.flight_path = flight_path
        if "base_url" not in self.__dict__:
            self.base_url = base_url
        if "rowwise" not in self.__dict__:
            self.rowwise = rowwise
        if "cleaning_required" not in self.__dict__:
            self.cleaning_required = cleaning_required
        if "shuttle_path" not in self.__dict__:
            self.shuttle_path = shuttle_path
        if "drop_table_on_success" not in self.__dict__:
            self.drop_table_on_success = drop_table_on_success
        if "jwt" not in self.__dict__:
            self.jwt = jwt
        if "org_engine" not in self.__dict__:
            self.org_engine = org_engine

        if not self.clean_table_name_root:
            raise ValueError("No clean table name specified")
        if atlas_organization_id is None and self.flight_path is None:
            raise ValueError("At least one organization ID or flight path must be specified!")
        

        # finish setup
        self.configuration = olpy.misc.get_config(jwt=self.jwt, base_url=self.base_url)
        self.flight = olpy.flight.Flight(configuration=self.configuration)
        if self.flight_path is not None:
            self.flight.deserialize(self.flight_path)
        else:
            self.flight.organization_id = atlas_organization_id

        # toggle between org_engine and individual user engine
        if self.org_engine:
            self.engine = self.flight.get_atlas_engine_for_organization()
        else:
            self.engine = self.flight.get_atlas_engine_for_individual_user()

    def clean_row(cls, row):
        raise NotImplementedError("clean_row is not defined for this integration.")

    def clean_df(cls, df):
        raise NotImplementedError("clean_df is not defined for this integration.")

    clean_row._unimplemented = True
    clean_df._unimplemented = True

    def determine_rowwise(self):
        self.rowwise = not getattr(self.clean_row, "_unimplemented", False)
        if self.cleaning_required and not self.rowwise and getattr(self.clean_df, "_unimplemented", False):
            print("No cleaning function implemented. Clean table will duplicate raw data.")
            self.cleaning_required = False

    def clean_and_upload(self):
        # Don't clean and upload if no sql or csv is specified
        if self.sql is None and self.csv is None:
            raise ValueError("Need at least one of sql or csv to run this function!")

        if self.rowwise is None:
            self.determine_rowwise()

        if self.standardize_clean_table_name:
            clean_table_name = olpy.clean.atlas.get_temp_table_name(
                self.clean_table_name_root
            )
        else:
            clean_table_name = self.clean_table_name_root

        dtypes = self.flight.get_pandas_datatypes_by_column()

        with self.engine.connect() as connection:

            if self.engine.dialect.has_table(connection, clean_table_name):
                if self.if_exists == "skip":
                    print("Clean table already exists. Skipping the cleaning step.")
                    print(f"{clean_table_name}")
                    return clean_table_name
                if self.if_exists == "replace":
                    print("Clean table already exists. Replacing...")
                    connection.execute(f"drop table {clean_table_name};")
                if self.if_exists == "fail":
                    raise Exception("Clean table name already in use.")

            # TODO parallelize rowwise cleaning
            if self.sql:
                generator = pd.read_sql_query(
                    self.sql,
                    connection,
                    chunksize=1000)
            elif self.csv:
                generator = pd.read_csv(self.csv, chunksize=1000)
            else:
                raise ValueError("Can only clean and upload if we have sql or csv!")
            rows_cleaned = 0
            rows_fetched = 0
            for chunk in generator:
                rows_fetched += len(chunk)
                cleaned_chunk = chunk
                if self.cleaning_required:
                    if self.rowwise:
                        cleaned_chunk = chunk.apply(self.clean_row, axis=1)
                    else:
                        dummy = self.clean_df(cleaned_chunk)
                        if dummy is not None:
                            cleaned_chunk = dummy
                cleaned_chunk.to_sql(
                    clean_table_name,
                    connection,
                    if_exists='append',
                    dtype={col: (dtypes[col] if col in dtypes.keys() else sqlalchemy.sql.sqltypes.String) for col in
                           cleaned_chunk.columns},
                    index=False,
                    chunksize=1000,
                    method='multi'
                )
                rows_cleaned += len(cleaned_chunk)
                print(f"Fetched and cleaned {rows_fetched} rows. Uploaded a total of {rows_cleaned} rows.")
            if rows_fetched == 0:
                # meaning original dataset was actually empty
                empty = pd.DataFrame(columns=dtypes.keys())
                empty.to_sql(
                    clean_table_name,
                    connection,
                    if_exists='append',
                    dtype=dtypes,
                    index=False
                )
                print(f"Input table is empty ! Uploaded a new empty table.")

        print("Cleaning completed successfully!")
        print(f"{clean_table_name}")
        return clean_table_name

    def integrate_table(self, clean_table_name=None, shuttle_path=None, shuttle_args=None, drop_table_on_success=None,
                        memory_size=None, local=False, sql=None, flight_path=None):

        if sql:
            data = pd.read_sql(sql, self.engine)
            if len(data.index) == 0:
                print(f"No data to upload for sql query {sql}")
                return

        environment = {
            "http://localhost:8080": "LOCAL",
            'https://api.openlattice.com': "PROD_INTEGRATION",
            'https://api.staging.openlattice.com': "STAGING_INTEGRATION"
        }

        # for ncric, make sure there's an __init__.py file if the yaml file is in a different place!
        if flight_path is not None:
            self.flight_path = resource_filename("pyntegrations", flight_path)
        if self.flight_path is None or not os.path.isfile(self.flight_path):
            raise ValueError("Flight path has not been specified or is incorrect!")

        host = environment[self.configuration.host]
        if local:
            token = olpy.misc.get_jwt(base_url="http://localhost:8080")
            host = "LOCAL"
        else:
            token = self.configuration.access_token

        integration_identifier = uuid.uuid4()
        tmp_mapper_path = f'/tmp/mapper_{integration_identifier}.yaml'

        up = re.findall("postgresql://(.*)@", str(self.engine.url))[0]
        up = unquote(up)
        username, password = up.split(":")

        if shuttle_path is None:
            shuttle_path = self.shuttle_path
        if drop_table_on_success is None:
            drop_table_on_success = self.drop_table_on_success

        retval = None

        mapper_dict = {
            'hikariConfigs': {
                str(integration_identifier): {
                    'jdbcUrl': f"jdbc:postgresql://{str(self.engine.url).split('@')[-1]}?ssl=true&sslmode=require",
                    'username': username,
                    "password": password,
                    'maximumPoolSize': 1
                }
            }
        }

        # create temp mapper file to pass to shuttle.
        # will delete on completion or exception.
        with open(tmp_mapper_path, "w") as m:
            yaml.dump(mapper_dict, m)

        try:
            if bool(clean_table_name) == bool(sql):
                raise ValueError("Exactly one of {clean_table_name, sql} must be specified.")

            if sql:
                sql = sql.replace('"', '\\"').replace('\\\\"', '\\"')
            else:
                sql = f"select * from {clean_table_name}"

            statement = f'{shuttle_path} --flight {self.flight_path} --token {token} --config {tmp_mapper_path} --datasource {integration_identifier} --sql "{sql}" --environment {host}'

            if shuttle_args:
                statement = f'{statement} {shuttle_args}'

            if memory_size is not None:
                statement = 'SHUTTLE_OPTS="-Xms{:n}g -Xmx{:n}g" '.format(memory_size, memory_size) + statement

            print(statement.replace(self.configuration.access_token, "***"))

            process = subprocess.Popen(statement, stdout=subprocess.PIPE, shell=True)
            try:
                while process.poll() is None:
                    output = process.stdout.readline()
                    if output:
                        print(output.strip().decode())
                retval = process.poll()
            except Exception as e:
                process.kill()
                raise
            process.kill()
        except Exception as e:
            track = traceback.format_exc()
            print(track)
            os.remove(tmp_mapper_path)
            raise
        os.remove(tmp_mapper_path)

        if retval != 0:
            raise ValueError("The integration did not exit cleanly...")

        print("Integration finished successfully!")
        if drop_table_on_success and clean_table_name:
            self.engine.execute(f"DROP TABLE {clean_table_name};")
            print(f"Dropped table {clean_table_name}")

    def integrate(self, shuttle_path=None, shuttle_args=None, drop_table_on_success=None):
        table = self.clean_and_upload()
        self.integrate_table(
            clean_table_name=table,
            shuttle_path=shuttle_path,
            shuttle_args=shuttle_args,
            drop_table_on_success=drop_table_on_success
        )
