from auth0.v3.authentication import GetToken
import openlattice
import os


def get_jwt(username=None, password=None, client_id=None, base_url='https://api.openlattice.com'):
    """
    Gets the jwt token for a given usr/pw from a given url.
    """

    domain = 'maiveric.us.auth0.com'
    realm = 'Username-Password-Authentication'
    scope = 'openid email nickname roles user_id organizations'

    envvars = {
        'rundeck': {
            'user': os.environ.get("RD_OPTION_OL_USER"),
            "password": os.environ.get("RD_OPTION_OL_PASS"),
            "client_id": os.environ.get("RD_OPTION_CLIENT_ID")
        },
        'local_to_local': {
            'user': os.environ.get("ol_user"),
            "password": os.environ.get("ol_password"),
            "client_id": os.environ.get("ol_client_id_local")
        },
        'local_to_prod': {
            'user': os.environ.get("ol_user"),
            "password": os.environ.get("ol_password"),
            "client_id":  os.environ.get('ol_client_id')
        }
    }

    environment = os.environ
    if 'RD_JOB_ID' in environment:
        env = 'rundeck'
    else:
        env = 'local_to_prod' if 'astrometrics.us' in base_url else 'local_to_local'
    env = envvars[env]

    if username:
        env['user'] = username
    if password:
        env['password'] = password
    if client_id:
        env['client_id'] = client_id
    if 'astrometrics.us' in base_url:
        base_url = f'https://{domain}/userinfo'

    if not (env['user'] and env['password'] and env['client_id']):
        raise ValueError("Not all necessary variables for authentication are present!")

    get_token = GetToken(domain)
    token = get_token.login(
        client_id=env['client_id'],
        client_secret="",
        username=env['user'],
        password=env['password'],
        scope=scope,
        realm=realm,
        audience=base_url,
        grant_type='http://auth0.com/oauth/grant-type/password-realm'
    )
    return token['id_token']


def get_config(jwt=None, base_url='https://api.openlattice.com'):
    if not jwt:
        jwt = get_jwt(base_url=base_url)
    configuration = openlattice.Configuration()
    configuration.host = base_url
    configuration.access_token = jwt

    return configuration


def drop_table(engine, table_name):
    """Drops a table. Useful for dropping intermediate tables
    after they are used in an integration"""
    try:
        engine.execute(f"DROP TABLE {table_name};")
        print(f"Dropped table {table_name}")
    except Exception as e:
        print(f"Could not drop main table due to {str(e)}")
