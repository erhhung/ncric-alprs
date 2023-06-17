import os
import re
import sys
import time
import json
import base64
import random
import openlattice
from datetime import datetime
from auth0.authentication import GetToken
from auth0.exceptions import RateLimitError


def get_jwt(client_id=None,
            username=None,
            password=None,
            base_url="http://datastore:8080"):
    """
    Gets the JWT token for a given user from a given URL.
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
        env = 'local_to_prod' if 'astrometrics' in base_url else 'local_to_local'
    env = envvars[env]

    if username:
        env['user'] = username
    if password:
        env['password'] = password
    if client_id:
        env['client_id'] = client_id
    if 'datastore' in base_url or 'astrometrics' in base_url:
        base_url = f'https://{domain}/userinfo'

    if not (env['user'] and env['password'] and env['client_id']):
        raise ValueError("Not all necessary variables for authentication are present!")

    # https://pypi.org/project/auth0-python/
    get_token = GetToken(domain, env['client_id'])

    # Allow retries with exponential backoff (5, 10, 20, 40 +/- 2 secs)
    # to accommodate errors such as API rate limits and network timeouts
    tries = 0
    delay = 0
    token = None
    while not token:
        try:
            token = get_token.login(
                #client_id=env['client_id'],
                #client_secret="",
                username=env['user'],
                password=env['password'],
                scope=scope,
                realm=realm,
                audience=base_url,
                grant_type='http://auth0.com/oauth/grant-type/password-realm')

        except Exception as e:
            tries += 1
            if tries == 10:
                msg = 'Giving up retrying Auth0 authentication!'
                print(msg, file=sys.stderr)
                raise e

            # RateLimitError: HTTP Status Code 429 (Too Many Requests)
            if isinstance(e, RateLimitError):
                msg = f'{e.status_code} Auth0 '
            else:
                msg = ''
            msg += f'{type(e).__name__}: {e.message}'
            print(msg, file=sys.stderr)

            # get next base backoff delay
            for backoff in 5, 10, 20, 40:
                if delay < backoff:
                    delay = backoff
                    break

            # prevent surge by adding +/- 2 seconds
            sleep = delay + random.randrange(-2, 3)
            msg = f'Retrying Auth0 authentication after {sleep} seconds...'
            print(msg, file=sys.stderr)
            time.sleep(sleep)

    # Auth0 JWT has an expiration of 10 hours
    return token['id_token']


def refresh_jwt_if_needed(jwt=None,
                          min_ttl_mins=120,
                          client_id=None,
                          username=None,
                          password=None,
                          base_url="http://datastore:8080"):
    """
    Checks the expiration of the given JWT and, if less than
    the minimum TTL (in minutes), gets a new JWT; otherwise,
    just returns the same JWT.
    """

    if jwt:
        try:
            claims = json.loads(base64.b64decode(jwt.split(".")[1] + "==").decode())
            ttl = datetime.fromtimestamp(claims["exp"]) - datetime.now()
            if ttl.seconds / 60 < min_ttl_mins:
                jwt = None
        except Exception as e:
            print(f"Could not determine JWT expiration due to: {str(e)}")
            jwt = None

    if not jwt:
        jwt = get_jwt(client_id=client_id,
                      username=username,
                      password=password,
                      base_url=base_url)
    return jwt


def get_config(jwt=None, base_url="http://datastore:8080"):
    if not jwt:
        jwt = get_jwt(base_url=base_url)
    configuration = openlattice.Configuration()
    configuration.host = base_url
    configuration.access_token = jwt
    return configuration


def drop_table(engine, table_name):
    """
    Drops a table. Useful for dropping intermediate tables
    after they are used in an integration.
    """

    try:
        engine.execute(f"DROP TABLE {table_name};")
        print(f"Dropped table {table_name}")
    except Exception as e:
        print(f"Could not drop main table due to: {str(e)}")


def entity_set_permissions(recipients_perms, entity_set_names, recip_type, configuration, action="ADD"):
    """
    Most common, most basic use case for permissions api.
    recipients_perms is something like this for email users:
    [
        ("email@openlattice.com", ["WRITE"]),
        ("user@jurisdiction.gov", ["READ", "WRITE", "OWNER"])
    ]
    or for roles:
    [
        ("00000000-0000-0000-0000-000000000000|JurisdictionOWNER", ["OWNER", "READ", "WRITE"]),
        ("00000000-0000-0000-0000-000000000000|JurisdictionREAD", ["READ"]),
        ("00000000-0000-0000-0000-000000000000|JurisdictionWRITE", ["WRITE"])
    ]

    entity_set_names is an iterable collection of entity set names
    recip_type is the type of username included in recipients_perms. Must be either "EMAIL"
    or a valid string to be passed to Principal as its type.
    configuration is used for constructing api instances
    action is what action to take (most commonly "ADD")
    """

    edm_api = openlattice.EdmApi(openlattice.ApiClient(configuration))
    permissions_api = openlattice.PermissionsApi(openlattice.ApiClient(configuration))
    entity_sets_api = openlattice.EntitySetsApi(openlattice.ApiClient(configuration))
    principal_api = openlattice.PrincipalApi(openlattice.ApiClient(configuration))

    new_rec_perms = []
    if recip_type == "EMAIL":
        for rp in recipients_perms:
            if re.match(".+@.+\\..+", rp[0]):
                user = principal_api.search_all_users_by_email(rp[0])
                new_rec_perms += [(x, rp[1]) for x in list(user.keys())]
            else:
                print(rp[0] + " is not an email address.")
        recipients_perms = new_rec_perms
        recip_type = "USER"

    for recipient, perms in recipients_perms:
        ace = openlattice.Ace(
            principal=openlattice.Principal(type=recip_type, id=recipient),
            permissions=perms
        )
        for entset_name in entity_set_names:
            try:
                entset_id = entity_sets_api.get_entity_set_id(entset_name)
                props = edm_api.get_entity_type(entity_sets_api.get_entity_set(entset_id).entity_type_id).properties

                acldata = openlattice.AclData(action=action,
                                              acl=openlattice.Acl(acl_key=[entset_id], aces=[ace]))

                permissions_api.update_acl(acldata)
                print("Giving permissions for entity set %s " % (entset_name))

                for prop in props:
                    acldata = openlattice.AclData(action=action,
                                                  acl=openlattice.Acl(acl_key=[entset_id, prop], aces=[ace]))
                    permissions_api.update_acl(acldata)
            except:
                print(entset_name, recipient, perms)
