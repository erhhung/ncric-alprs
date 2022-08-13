from auth0.v3.authentication import GetToken
import openlattice
import os
import re


def get_jwt(username=None, password=None, client_id=None, base_url='https://api.astrometrics.us'):
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
    if not 'astrometrics.us' in base_url:
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
        audience=f'https://{domain}/userinfo',
        grant_type='http://auth0.com/oauth/grant-type/password-realm'
    )
    return token['id_token']


def get_config(jwt=None, base_url='https://api.astrometrics.us'):
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


def entity_set_permissions(recipients_perms, entity_set_names, recip_type, configuration, action="ADD"):
    '''
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
    '''

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