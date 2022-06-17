from pytz import timezone
import sqlalchemy as sq
import pandas as pd
import openlattice
import datetime
import urllib
import yaml
import olpy
import re
import os
from geoalchemy2 import Geometry, WKTElement

def get_temp_table_name(table_name, dt=datetime.datetime.now(timezone("US/Pacific"))):
    """
    Produces the name of a temp table based on the original name and the current PST.

    Convention followed: zzz_<original name>_yyyy_(m)m_(d)d_(h)h_(m)m_(s)s_pst.
    """

    dt_string = "_".join([str(dt.year), str(dt.month), str(dt.day), str(dt.hour), str(dt.minute), str(dt.second)])
    return "zzz_%s_%s_pst" % (table_name, dt_string)

def get_atlas_engine_for_individual_user(organization_id, configuration):
    if not configuration:
        configuration = olpy.get_config()

    principal_api = openlattice.PrincipalApi(openlattice.ApiClient(configuration))
    organizations_api = openlattice.OrganizationsApi(openlattice.ApiClient(configuration))
    account = principal_api.get_materialized_view_account()
    # org_db = "org_"+organization_id.replace("-", "")
    org_db = organizations_api.get_organization_database_name(organization_id)

    jdbc_url = f'''postgresql://{account.username}:{account.credential}@atlas.openlattice.com:30001/{org_db}'''

    engine = sq.create_engine(jdbc_url)

    return engine

def get_atlas_engine_for_organization(organization_id, configuration):
    if not configuration:
        configuration = olpy.get_config()

    organizations_api = openlattice.OrganizationsApi(openlattice.ApiClient(configuration))
    account = organizations_api.get_organization_integration_account(organization_id)
    org_db = organizations_api.get_organization_database_name(organization_id)

    jdbc_url = f'''postgresql://{account.user}:{account.credential}@atlas.openlattice.com:30001/{org_db}'''

    engine = sq.create_engine(jdbc_url)

    return engine


def get_atlas_engine(db_name, db_password, usr_name=None):
    """
    Returns sqlalchemy engine for the atlas database with the given usr/pw/db name.
    """

    if usr_name is None:
        usr_name = db_name
    return sq.create_engine(
        'postgresql://%s:%s@atlas.openlattice.com:30001/%s' \
        % (usr_name, urllib.parse.quote_plus(db_password), db_name),
        connect_args={'sslmode': 'require'}
    )

def drop_table(engine, table_name):
    """Drops a table. Useful for drropping intermediate tables
    after they are used in an integration"""
    try:
        engine.execute(f"DROP TABLE {table_name};")
        print(f"Dropped table {table_name}")
    except Exception as e:
        print(f"Could not drop main table due to {str(e)}")

def overwrite_tables(df, table_name, engine, geom_data_type = None, geometry_col = None, crs = None):
    """
    Overwrites tables without deleting table by truncating table first
    then appending data
    If table does not exist, then pass the truncation and append
    If table names change, then error out
    """
    try:
        engine.execute(f"TRUNCATE TABLE {table_name}")
    except sq.exc.ProgrammingError as e:
        if "psycopg2.errors.UndefinedTable" in str(e):
            pass

    if geometry_col is not None:
        df.to_sql(table_name, 
                   engine, 
                   if_exists='append', 
                    index=False, 
                    dtype={geometry_col: Geometry(geom_data_type, srid= crs)})
    else:
        df.to_sql(table_name, engine, if_exists = "append", index = False)


def get_atlas_engine_from_mapper(config_file, datasource):
    """
    Returns sqlalchemy engine for the atlas database with the given shuttle configuration file and datasource.
    """

    with open(config_file, 'r') as fl:
        mapper = yaml.load(fl, Loader=yaml.FullLoader)

    jdbc = mapper['hikariConfigs'][datasource]['jdbcUrl']
    username = mapper['hikariConfigs'][datasource]['username']
    password = mapper['hikariConfigs'][datasource]['password']

    jdbc = re.search('jdbc:(.*?)\?', jdbc).group(1) \
        .replace("postgresql://", "postgresql://{username}:{password}@".format(
        username=username,
        password=password
    ))

    return sq.create_engine(
        jdbc,
        connect_args={'sslmode': 'require'}
    )

def select_tables(labeled_sqls, df_pred, con):
    """
    Gets a dict of predicate-matching dataframes from a db connection.
    """

    selected = dict()
    for label, sql in labeled_sqls.items():
        df = pd.read_sql(sql, con=con)
        if df_pred(df):
            selected[label] = sql
    return selected


def limit_query(sql, limit):
    """
    Adds a limit clause to a query.
    """

    return "%s limit %s;" % (sql.replace(";", ""), limit)


def cols_to_string_with_dubquotes(cols, backslash=False):
    """
    Gets a string representation of a list of strings, using double quotes.

    Useful for converting list of columns to a string for use in a query.
    Backslashes are possible if the query will be passed as a string argument to (for instance) Shuttle.
    """

    if backslash:
        return '\\"%s\\"' % ('\\", \\"'.join(cols))
    return '"%s"' % ('", "'.join(cols))


def count_rows(sql, con):
    """
    Gets the number of rows returned by a query.
    """

    sql = sql.replace(";", "")
    df = pd.read_sql("select count(*) from (%s) foo;" % sql, con)
    return df["count"].iloc[0]


def get_cols_from_sql(sql, con):
    """
    Gets the column names from a database query result.
    """

    return pd.read_sql(limit_query(sql, 1), con).columns

def get_datatypes(table_name, engine):
    '''
    Gets a pandas.DataFrame with column datatypes for a given table and sqlalchemy.Engine

    :param table_name: string
    :param engine: sqlalchemy.Engine
    :return: pandas.DataFrame
    '''
    dt_list = '''
    SELECT column_name, data_type
    FROM information_schema.columns
    where table_name = '{table_name}';
    '''.format(table_name=table_name)
    return pd.read_sql(dt_list, engine).set_index('column_name')