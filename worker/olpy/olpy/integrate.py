
import openlattice
import numpy as np
import pandas as pd
from . import clean
import re

def collect_all_accessible(auth_api, object_types = ["Role", "Organization", "EntitySet", "PropertyTypeInEntitySet"], permissions = ["OWNER", "READ", "WRITE"]):
    """
    Creates a dict with outputs of get_all_accessible_at_permission_level over various object_types and permission levels

    Output format is dict({
        tuple(principal_1): ["OWNER"],
        tuple(principal_2): ["READ"],
        tuple(principal_3): ["READ", "WRITE"]
    })
    """

    out = dict()
    for perm in permissions:
        for object_type in object_types:
            api_output = auth_api.get_accessible_objects(object_type = object_type, permission = perm)
            accessibles = [tuple(a) for a in api_output.authorized_objects]
            for a in accessibles:
                if a in out.keys():
                    out[a].append(perm)
                else:
                    out[a] = [perm]
    return out


def transfer_owner_permissions(
    configuration,
    recipient,
    object_types = ["Role", "Organization", "EntitySet", "PropertyTypeInEntitySet"],
    recipient_auth_api = None
):
    """
    Transfers ownership permissions on all objects of specified type from the user specified in the configuration to the given recipient user ID. Permission granting seems to be fairly slow (~10 per second), even if the recipient already had access. If you have the recipient's token, you can optionally provide an instance of their auth_api. This makes skipping the things they already have access to much faster.
    """

    auth_api = openlattice.AuthorizationsApi(openlattice.ApiClient(configuration))
    permissions_api = openlattice.PermissionsApi(openlattice.ApiClient(configuration))
    all_accessible = collect_all_accessible(auth_api, object_types = object_types, permissions = ["OWNER"])

    to_skip = set()
    if recipient_auth_api is not None:
        already_accessible = collect_all_accessible(recipient_auth_api, object_types = object_types, permissions = ["OWNER"])
        to_skip = set(already_accessible.keys())

    print("Finished collecting all accessible objects!")
    print("Transferring...")
    total_transferred = 0
    target = len(all_accessible) - len(to_skip)
    for o, perms in all_accessible.items():
        if o not in to_skip:
            acl_key = list(o)

            ace = openlattice.Ace(
                    principal = openlattice.Principal(type="USER", id=recipient),
                    permissions = perms
            )
            try:
                acldata = openlattice.AclData(
                    action = "ADD", 
                    acl = openlattice.Acl(acl_key = acl_key, aces = [ace])
                )
                permissions_api.update_acl(acldata)
                total_transferred += 1
                if total_transferred % 100 == 0:
                    print(f"Transferred permissions for {total_transferred} out of {target} objects")
            except Exception as exc:
                print("Failed to give permissions on " + str(acl_key))
                print(exc)
            

def integration_checksums(
    flight,
    configuration,
    sql = None,
    engine = None,
    df = None,
    entity_set_names = None,
    check_random_n_entity_sets = None
    ):
    """
    For a given list of entity sets, checks the number of unique pk values in source data against those integrated

    The list of entity sets to check may be passed explicitly or else compiled at random to length n.
    """

    entity_sets_api = openlattice.EntitySetsApi(openlattice.ApiClient(configuration))
    data_api = openlattice.DataApi(openlattice.ApiClient(configuration))
    
    all_ent_assn_defns = list(flight.entity_definitions.values()) + list(flight.association_definitions.values())

    if not entity_set_names:
        entity_set_names = list(set([x.entity_set_name for x in all_ent_assn_defns]))
        if check_random_n_entity_sets:
            check_random_n_entity_sets = min(check_random_n_entity_sets, len(entity_set_names))
            entity_set_names = np.random.choice(entity_set_names, size = check_random_n_entity_sets, replace = False)

    compiled = [
        (entity_set_name, set([frozenset(x.get_columns_from_pk()) for x in all_ent_assn_defns if x.entity_set_name == entity_set_name])) for entity_set_name in entity_set_names
    ]

    out = dict()

    if sql:
        sql = sql.replace(";", "")

    for entity_set_name, col_lists in compiled:
        lower = 0
        upper = 0
        if not col_lists:
            lower = 1 # singleton entity definition
            upper = 1
        else:
            for col_list in col_lists:
                additional = 1
                if sql:
                    additional = pd.read_sql("select count(distinct(" + clean.cols_to_string_with_dubquotes(col_list) + ")) from (" + sql + ") foo", engine)["count"].iloc[0]
                elif df:
                    additional = len(df[col_list].unique())
                lower += additional - 1 # empty pks are not written to prod
                upper += additional
        out[entity_set_name] = (lower, upper, data_api.get_entity_set_size(entity_sets_api.get_entity_set_id(entity_set_name)))
    return out



def test_auth(configuration):
    """
    Tests a configuration for authentication by attempting to access the DemoPatients entity set
    """

    entity_sets_api = openlattice.EntitySetsApi(openlattice.ApiClient(configuration))
    try:
        entity_sets_api.get_entity_set_id(entity_set_name="DemoPatients")
        return True
    except:
        return False


def entity_set_permissions(recipients_perms, entity_set_names, recip_type, configuration, action = "ADD"):
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
                principal = openlattice.Principal(type=recip_type, id=recipient),
                permissions = perms
            )

        for entset_name in entity_set_names:
            try:
                entset_id = entity_sets_api.get_entity_set_id(entset_name)
                props = edm_api.get_entity_type(entity_sets_api.get_entity_set(entset_id).entity_type_id).properties

                acldata = openlattice.AclData(action = action, 
                    acl = openlattice.Acl(acl_key = [entset_id], aces = [ace]))
                
                permissions_api.update_acl(acldata)
                print("Giving permissions for entity set %s " % (entset_name))

                for prop in props:
                    acldata = openlattice.AclData(action = action, 
                        acl = openlattice.Acl(acl_key = [entset_id,prop], aces = [ace]))
                    permissions_api.update_acl(acldata)
            except:
                print(entset_name, recipient, perms)



                
