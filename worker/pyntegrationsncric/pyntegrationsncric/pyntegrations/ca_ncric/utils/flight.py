import openlattice
from sqlalchemy.types import *
from collections import Counter
import pandas as pd
import yaml
import re

"""
    This file is a direct copy of parts of https://github.com/openlattice/olpy/blob/main/olpy/flight/flight.py,
    put here to enable this repository to be standalone.
"""


class PropertyDefinition(object):
    """
    A class representing a property definition
    """

    def __init__(self, type="", column="", transforms=[], definition_dict=dict(), edm_api=None):
        if not isinstance(definition_dict, dict):
            print("Attempting to automatically interpret %s as a property definition..." % str(definition_dict))
            if isinstance(definition_dict, str):
                self.type = type
                self.column = column
                self.transforms = [
                    {"transforms.ValueTransform": None, "value": definition_dict}
                ]
            elif isinstance(definition_dict, list):
                self.type = type
                self.column = column
                self.transforms = [
                    {"transforms.ConcatTransform": None, "columns": definition_dict, "separator": "-"}
                ]
        else:
            self.type = type if type else (definition_dict['type'] if 'type' in definition_dict.keys() else "")
            self.column = column if column else (
                definition_dict['column'] if 'column' in definition_dict.keys() else "")

            if "columns" in definition_dict.keys():
                print("Attempting to coerce %s to a ConcatTransform" % str(definition_dict["columns"]))
                self.transforms = [
                    {"transforms.ConcatTransform": None, "columns": definition_dict["columns"], "separator": "-"}
                ]
            elif "value" in definition_dict.keys():
                print("Attempting to coerce %s to a ValueTransform" % str(definition_dict["value"]))
                self.transforms = [
                    {"transforms.ValueTransform": None, "value": definition_dict["value"]}
                ]
            else:
                self.transforms = transforms if transforms else (
                    definition_dict['transforms'] if 'transforms' in definition_dict.keys() else [])
        self.edm_api = edm_api
        self.property_type = None

    def get_property_type(self):
        """
        Gets the property type ID.
        """

        if not self.property_type:
            self.load_property_type()
        return self.property_type

    def load_property_type(self):
        """
        Reads the property type definition from API into an instance variable.
        """

        fqn = self.type.split(".")
        if len(fqn) < 2:
            return
        try:
            self.property_type = self.edm_api.get_property_type(
                self.edm_api.get_property_type_id(namespace=fqn[0], name=fqn[1]))
        except openlattice.rest.ApiException as exc:
            self.property_type = openlattice.PropertyType(
                type=openlattice.FullQualifiedName()
            )

    def add_datatype_parser_if_needed(self, timezone=None):
        """
        Creates a parsing transformation within this property definition if it is needed.

        String formats for times and datetimes are assumed to be in ["HH:mm:ss", "HH:mm:ss.S", "HH:mm:ss.SS", "HH:mm:ss.SSS"]
        and ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.S", "yyyy-MM-dd HH:mm:ss.SS", "yyyy-MM-dd HH:mm:ss.SSS"] respectively.
        As such, manually checking the string formats in the source data and updating the flight as needed is a required step
        following the use of this function.
        """

        datatype = self.get_property_type().datatype
        parse_req = {
            'TimeOfDay': ["transforms.TimeTransform"],
            'Int64': ["transforms.ParseIntTransform"],
            'Int32': ["transforms.ParseIntTransform"],
            'Int16': ["transforms.ParseIntTransform"],
            'Boolean': ["transforms.ParseBoolTransform"],
            'Binary': ["transforms.ParseBoolTransform"],
            'Double': ["transforms.ParseDoubleTransform"],
            'Date': ["transforms.DateTimeAsDateTransform", "transforms.DateTransform"],
            'DateTimeOffset': ["transforms.DateTimeTransform", "transforms.DateAsDateTimeTransform"]
        }
        if datatype in parse_req.keys():
            these_transforms = _get_transforms_used_in(self.transforms)
            compliance = set(parse_req[datatype]) & these_transforms
            if not compliance:
                transform = {
                    parse_req[datatype][0]: None
                }
                arg_dict = dict()
                if datatype == "TimeOfDay":
                    transform["pattern"] = ["HH:mm:ss", "HH:mm:ss.S", "HH:mm:ss.SS", "HH:mm:ss.SSS"]
                    if timezone is not None:
                        transform["timezone"] = timezone
                elif datatype == "Date" or datatype == "DateTimeOffset":
                    transform["pattern"] = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.S", "yyyy-MM-dd HH:mm:ss.SS",
                                            "yyyy-MM-dd HH:mm:ss.SSS"]
                    if timezone is not None:
                        transform["timezone"] = timezone
                if self.transforms:
                    self.transforms.append(transform)
                else:
                    self.transforms = [transform]

    def get_schema(self):
        """
        Gets the schema of this property definition.

        Called by the enclosing EntityDefinition's get_schema()
        """

        out = {
            "fqn": self.type,
            "column": self.column
        }
        # if isinstance(self.transforms, list):
        #     out['transforms'] = _parse_transforms(self.transforms)
        return out

    def get_columns(self):
        """
        Gets the columns referenced in this property definition.

        The recursive logic used by this function includes string matching heuristics that
        may not be stable against changes in flight syntax specifications.
        """

        schema = self.get_schema()
        columns = {schema['column']} if schema['column'] else set()
        if 'transforms' in schema.keys():
            columns = columns | set(schema['transforms']['columns'])
        return columns


class EntityDefinition(object):
    """
    A class representing an entity definition
    """

    def __init__(self, definition_dict=dict(), edm_api=None, entity_sets_api=None):
        self.name = definition_dict['name'] if 'name' in definition_dict.keys() else ""
        self.fqn = definition_dict['fqn'] if 'fqn' in definition_dict.keys() else ""
        self.entity_set_name = definition_dict['entitySetName'] if 'entitySetName' in definition_dict.keys() else ""
        self.conditions = definition_dict['conditions'] if 'conditions' in definition_dict.keys() else []
        self.update_type = definition_dict['updateType'] if 'updateType' in definition_dict.keys() else "Merge"

        self.edm_api = edm_api
        self.entity_sets_api = entity_sets_api

        self.entity_type = None

        # deserialize and check property definitions
        self.property_definitions = {}
        if "propertyDefinitions" in definition_dict.keys():
            for key, defn in definition_dict[
                    'propertyDefinitions'].items():  # todo double check removing automatic key-to-type doesn't break anything
                self.property_definitions[key] = PropertyDefinition(definition_dict=defn, edm_api=edm_api)

    def get_entity_type(self):
        """
        Gets the entity type.
        :return: openlattice.EntityType
        """
        if not self.entity_type:
            self.load_entity_type()
        return self.entity_type

    def load_entity_type(self):
        """
        Calls the API and loads the entity type information into an instance variable.
        """

        fqn = self.fqn.split(".")
        if len(fqn) < 2:
            return
        try:
            self.entity_type = self.edm_api.get_entity_type(
                self.edm_api.get_entity_type_id(namespace=fqn[0], name=fqn[1]))

        except openlattice.rest.ApiException as exc:
            self.entity_type = openlattice.EntityType(
                type=openlattice.FullQualifiedName(),
                key=[],
                properties=[]
            )

    def add_pk_if_missing(self, infer_columns=False, columns=[], hash_by_default=True, suffix=None):
        """
        Generates a property type for the pk of this entity definition, if needed.

        Columns are either pulled from the rest of the entity definition or passed explicitly. Then they are either
        fed into a HashTransform (using SHA 256) or a simple ConcatTransform. An optional suffix is appended if the
        columns alone would fail to distinguish between two entities written to one entity set (this usually happens with
        associations).
        """

        if infer_columns:
            columns = self.get_columns()
        columns = list(columns)
        keys = {"ol.id"}
        pk_type_ids = self.get_entity_type().key
        if pk_type_ids:
            key_types = [self.edm_api.get_property_type(p) for p in pk_type_ids]
            keys = set(["%s.%s" % (pk_type.type.namespace, pk_type.type.name) for pk_type in key_types])

        these = set(self.property_definitions.keys())
        overlap = keys & these
        if len(overlap) == 0:
            pk = keys.pop()
            self.property_definitions[pk] = PropertyDefinition(type=pk, edm_api=self.edm_api)
            if not hash_by_default:
                if len(columns) == 1:
                    self.property_definitions[pk].column = columns[0]
                elif len(columns) > 1:
                    self.property_definitions[pk].transforms = [
                        {"transforms.ConcatTransform": None, "columns": columns}]
            else:
                self.property_definitions[pk].transforms = [
                    {"transforms.HashTransform": None, "columns": columns, "hashFunction": "sha256"}]
            if suffix:
                self.property_definitions[pk].transforms = [
                    {
                        "transforms.ConcatCombineTransform": None,
                        "transforms": self.property_definitions[pk].transforms + [
                            {
                                "transforms.ValueTransform": None,
                                "value": suffix
                            }
                        ]
                    }
                ]

    def auto_generate_conditions(self):
        """
        Add not-null conditions for all columns if there is a ValueTransform and no conditions already exist.
        """

        if not self.conditions:
            for property in self.property_definitions.values():
                if "transforms.ValueTransform" in _get_transforms_used_in(property.transforms):
                    conditions = []
                    columns = self.get_columns()
                    if columns:
                        if len(columns) > 1:
                            conditions.append({'conditions.ConditionalOr': {}})
                        for c in columns:
                            conditions.append({'conditions.BooleanIsNullCondition': None, 'column': c, 'reverse': True})
                        self.conditions = conditions

    def sort_properties_for_writing(self):
        """
        Lists the property definitions with the primary key first, if it exists.
        """

        try:
            ent_type = self.edm_api.get_entity_type(self.entity_type_id)
            key_types = [self.edm_api.get_property_type(x) for x in ent_type.key]
            pks = set(["%s.%s" % (x.type.namespace, x.type.name) for x in key_types])
            these_props = self.property_definitions.items()
            for prop in these_props:
                if prop[0] in pks or prop[1].type in pks:
                    return [prop] + [x for x in these_props if x[0] != prop[0]]
        except:
            return list(self.property_definitions.items())

    def get_schema(self):
        """
        Gets the schema.
        """

        out = {
            "fqn": self.fqn,
            "entity_set_name": self.entity_set_name,
            "name": self.name,
            "properties": [x.get_schema() for x in self.property_definitions.values()]
        }
        # if isinstance(self.conditions, list):
        #     out['conditions'] = _parse_conditions(self.conditions)
        return out

    def get_columns(self):
        """
        Returns the set of columns referenced in this entity definition.

        The recursive logic used by this function includes string matching heuristics that
        may not be stable against changes in flight syntax specifications.
        """

        cols = set()
        for property in self.property_definitions.values():
            cols = cols.union(property.get_columns())
        return set(cols)

    def get_columns_from_pk(self):
        """
        Returns the set of columns used by the primary key property definitions in this entity definition.
        """

        cols = set()
        keys = self.get_entity_type().key
        if keys:
            for property in self.property_definitions.values():
                if property.get_property_type().id in keys:
                    cols = cols | property.get_columns()
            return cols
        else:
            for property in self.property_definitions.values():
                if property.type == "ol.id":
                    return property.get_columns()


class AssociationDefinition(EntityDefinition):
    """
    A class representing an association definition

    An AssociationDefinition is an EntityDefinition with a defined source and destination.
    """

    def __init__(self, definition_dict=dict(), src_alias="", dst_alias="", edm_api=None, entity_sets_api=None):
        super().__init__(definition_dict=definition_dict, edm_api=edm_api, entity_sets_api=entity_sets_api)
        # src and dst are EntityDefinitions unless they aren't defined in the flight, in which case they are set to the src and dst strings given in the definition_dict.
        self.src_alias = src_alias if src_alias else (definition_dict["src"] if "src" in definition_dict.keys() else "")
        self.dst_alias = dst_alias if dst_alias else (definition_dict["dst"] if "dst" in definition_dict.keys() else "")
        self.association_type = None

    def get_association_type(self):
        """
        Gets the entity type.
        :return: openlattice.AssociationType
        """
        if not self.association_type:
            self.load_association_type()
        return self.association_type

    def get_entity_type(self):
        """
        Gets the entity type.
        :return: openlattice.EntityType
        """
        if not self.association_type:
            self.load_association_type()
        return self.association_type.entity_type

    def load_association_type(self, edm=None):
        """
        Calls API and loads the entity type and association type information into an instance variable
        """

        fqn = self.fqn.split(".")
        if len(fqn) < 2:
            return
        try:
            self.association_type = self.edm_api.get_association_type(
                self.edm_api.get_entity_type_id(namespace=fqn[0], name=fqn[1]))
        except openlattice.rest.ApiException as exc:
            self.association_type = openlattice.AssociationType(
                entity_type=openlattice.EntityType(
                    type=openlattice.FullQualifiedName(),
                    key=[],
                    properties=[]
                ),
                src=[],
                dst=[]
            )
        self.entity_type = self.association_type.entity_type

    def get_schema(self):
        """
        Gets the schema.
        """

        out = super().get_schema()
        out.update({
            "src": self.src_alias,
            "dst": self.dst_alias
        })
        return out


class Flight(object):
    """
    A class representing a flight script
    """

    def __init__(self, name="", organization_id=None, configuration=None, path=None):

        self.name = name
        self.entity_definitions = dict()
        self.association_definitions = dict()
        self.configuration = configuration

        self.organization_id = organization_id
        self.edm_api = openlattice.EdmApi(openlattice.ApiClient(self.configuration))
        self.entity_sets_api = openlattice.EntitySetsApi(openlattice.ApiClient(self.configuration))
        if path:
            self.deserialize(path)

    def __str__(self):
        """
        A function that produces a string representation of the flight

        The following conventions are upheld:
        - Two-space indentation
        - Entity definitions are written before association definitions.
        - Entities that are more connected appear earlier.
        - Primary keys appear ahead of property definitions.
        - Association definitions are grouped by fqn and sorted by the alias's trailing integer.
        """

        out_string = "organizationId: {organization_id}\n".format(organization_id=self.organization_id)
        depth = 2
        for def_type in ['entityDefinitions', 'associationDefinitions']:
            sorted_ent_defs = self._sort_entities_for_writing(
                "entity" if def_type == "entityDefinitions" else "association")
            if len(sorted_ent_defs) == 0:
                out_string += def_type + ': {}'
                continue
            out_string += def_type + ':\n'
            for alias, entity in sorted_ent_defs:
                out_string += " " * depth + alias + ":\n"
                depth += 2
                out_string += " " * depth + 'fqn: "' + entity.fqn + '"\n'
                out_string += " " * depth + 'entitySetName: "' + entity.entity_set_name + '"\n'
                if len(entity.update_type) > 0:
                    out_string += " " * depth + 'updateType: "' + entity.update_type + '"\n'
                if def_type == 'associationDefinitions':
                    out_string += " " * depth + 'src: "' + entity.src_alias + '"\n'
                    out_string += " " * depth + 'dst: "' + entity.dst_alias + '"\n'
                out_string += " " * depth + 'propertyDefinitions:\n'
                depth += 2
                sorted_prop_defs = entity.sort_properties_for_writing()
                for prop_alias, prop_defn in sorted_prop_defs:
                    out_string += " " * depth + prop_alias + ':\n'
                    depth += 2
                    out_string += " " * depth + 'type: "' + prop_defn.type + '"\n'
                    if prop_defn.column:
                        out_string += " " * depth + 'column: "' + prop_defn.column + '"\n'
                    depth -= 2
                depth -= 2
                out_string += " " * depth + 'name: "' + entity.name + '"\n\n'
                depth -= 2
        return out_string.replace('\\', "\\\\")

    def _sort_entities_for_writing(self, def_type='entity'):
        if def_type == 'entity':
            # sort entities by how well-associated they are
            return sorted(self.entity_definitions.items(),
                          key=lambda pair: sum([1 for x in self.association_definitions.values() if
                                                {x.src_alias, x.dst_alias}.intersection({pair[0], pair[1].name})]),
                          reverse=True)
        else:
            # bunch associations by fqn, sorting by trailing integer in the alias
            fqns = set([v.fqn for v in self.association_definitions.values()])
            out = []
            for fqn in fqns:
                out += sorted([x for x in self.association_definitions.items() if x[1].fqn == fqn],
                              key=lambda pair: int("0" + re.search("[0-9]*$", pair[0]).group()))
            return out

    def deserialize(self, filename):
        """
        Populates this flight's entity and association definitions with a deserialized yaml file
        """

        string = open(filename).read()
        self.deserialize_from_string(string)

    def deserialize_from_string(self, string):
        """
        Populates this flight's entity and association definitions with a deserialized dictionary string
        """

        reformat = "\n".join(string.split("\n"))
        reformat = reformat.replace("!<generators.TransformSeriesGenerator>", "")
        reformat = reformat.replace("- !<", "- ")
        reformat = reformat.replace(">", ":")

        flight_dict = yaml.load(reformat, Loader=yaml.FullLoader)
        if not 'organizationId' in flight_dict.keys():
            raise ValueError("Flights require specification of the organization ID.")
        self.organization_id = flight_dict['organizationId']

        for key, defn in flight_dict['entityDefinitions'].items():
            self.entity_definitions[key] = EntityDefinition(
                definition_dict=defn,
                edm_api=self.edm_api,
                entity_sets_api=self.entity_sets_api
            )

        for key, defn in flight_dict['associationDefinitions'].items():
            self.association_definitions[key] = AssociationDefinition(
                definition_dict=defn,
                edm_api=self.edm_api,
                entity_sets_api=self.entity_sets_api,
                src_alias=defn["src"],
                dst_alias=defn["dst"]
            )
        print("Finished deserializing the flight!")

    def make_entity_defn_dict(self, entpropstring):

        # make properties
        p_dict = {}
        p_pattern = r"-\s+(\S+)\s+\((\S+)\)"
        p_matches = re.findall(p_pattern, entpropstring, re.MULTILINE)
        for match in p_matches:
            p_dict[match[1]] = {"column": match[0], "type": match[1]}

        # make entities
        e_pattern = r"^(\S+)\s+\[(\S+)\]\s+\((\S+)\)"
        e_match = re.match(e_pattern, entpropstring)
        e_dict = {e_match[1]: {}}

        e_dict[e_match[1]]['name'] = e_match[1]
        e_dict[e_match[1]]['entitySetName'] = e_match[2]
        e_dict[e_match[1]]['fqn'] = e_match[3]
        e_dict[e_match[1]]['propertyDefinitions'] = p_dict

        return e_dict

    def make_association_defn_dict(self, assnpropstring):

        # make properties
        p_dict = {}
        p_pattern = r"-\s+(\S+)\s+\((\S+)\)"
        p_matches = re.findall(p_pattern, assnpropstring, re.MULTILINE)
        for match in p_matches:
            p_dict[match[1]] = {"column": match[0], "type": match[1]}

        # make associations
        assn_pattern = r"(\S+)\s+(?:->|→|-->)\s+(\S+)\s+\[(\S+)\]\s+\((\S+)\)\s+(?:->|→|-->)\s+(\S+)"
        assn_match = re.match(assn_pattern, assnpropstring)
        assn_dict = {assn_match[2]: {}}

        assn_dict[assn_match[2]]['src'] = assn_match[1]
        assn_dict[assn_match[2]]['name'] = assn_match[2]
        assn_dict[assn_match[2]]['entitySetName'] = assn_match[3]
        assn_dict[assn_match[2]]['fqn'] = assn_match[4]
        assn_dict[assn_match[2]]['dst'] = assn_match[5]
        assn_dict[assn_match[2]]['propertyDefinitions'] = p_dict

        return assn_dict

    def get_all_columns(self):
        """
        Returns a set containing all column names referenced in this flight

        The recursive logic used by this function and its subroutines include string matching heuristics that
        may not be stable against changes in flight syntax specifications.
        """

        cols = set()
        for ent in self.entity_definitions.values():
            cols = cols.union(ent.get_columns())
        for assn in self.association_definitions.values():
            cols = cols.union(assn.get_columns())
        return cols

    def get_entity_definition_by_name(self, name):
        """
        Looks up an entity definition first by alias (dictionary key lookup), then by name (iteration)
        """

        if name in self.entity_definitions.keys():
            if not self.entity_definitions[name].name or self.entity_definitions[name].name == name:
                return self.entity_definitions[name]
        for entity in self.entity_definitions.values():
            if entity.name == name:
                return entity

    def get_all_entity_sets(self, remove_prefix="", add_prefix="", add_suffix="", contacts=[]):
        """
        Gets all entity set information.

        Output is a list of entries of the form: {
            "entity_type_id": <entity type id>,
            "name": <entity set name>,
            "title": <entity set title - deduced from entity set name>,
            "contacts": <contact list>
        }
        """

        checker = {}
        out = []
        for ent in list(self.entity_definitions.values()) + list(self.association_definitions.values()):
            if not ent.entity_set_name in checker.keys():
                checker[ent.entity_set_name] = ent.fqn
                entset = {
                    "entity_type_id": ent.get_entity_type().id,
                    "name": ent.entity_set_name,
                    "title": "%s%s%s" % (add_prefix, ent.entity_set_name.replace(remove_prefix, ""), add_suffix),
                    "contacts": contacts
                }
                out.append(entset)
            else:
                if not checker[ent.entity_set_name] == ent.fqn:
                    raise ValueError("%s is registered for different fqn's !" % ent.entity_set_name)
        return out

    def get_datatypes(self):
        """
        Returns a dict of fqn: datatype pairs present in this flight.
        """

        # if not hasattr(self.entity_definitions[0].property_definitions[0], '_property_type_id'):
        #     self.add_and_check_edm()
        datatypes = {}
        for ent in list(self.entity_definitions.values()) + list(self.association_definitions.values()):
            for propertydef in ent.property_definitions.values():
                datatypes[propertydef.type] = propertydef.get_property_type().datatype
        return datatypes

    def get_datatypes_by_column(self):
        """
        Returns a dict of column: datatype pairs present in this flight.
        """

        entities = list(self.entity_definitions.values()) + list(self.association_definitions.values())
        print(entities)
        datatypes = [
            {"column": propertydef.column, "datatype": propertydef.get_property_type().datatype}
            for ent
            in entities
            for propertydef
            in ent.property_definitions.values()
        ]
        print(datatypes) #kim
        # make sure that each column has one unique datatype
        deduped = pd.DataFrame(datatypes).drop_duplicates().set_index('column')
        counter = dict(Counter(deduped.index))

        # initiate with non-conflicting
        dtype_map = {k: deduped.loc[k].datatype for k, v in counter.items() if v == 1}

        # take care of conflicts
        for double in [k for k, v in counter.items() if v > 1]:
            values = list(deduped.loc[double].datatype)
            non_string = [x for x in values if not x == 'String']
            if len(non_string) == 0:
                dtype_map[double] = 'String'
            if len(non_string) == 1:
                dtype_map[double] = non_string[0]
            else:
                outstr = """
                Mismatch in datatypes:
                The column {column} is expected to be: {formats}.
                """.format(
                    column=double,
                    formats=", ".join(values)
                )
        return dtype_map

    def get_pandas_datatypes_by_column(self):
        mapper = self.get_datatypes_by_column()
        datatypes_map = {
            "Int64": Integer,
            "Int32": Integer,
            "Int16": Integer,
            "Boolean": Boolean,
            "DateTimeOffset": TIMESTAMP(timezone=True),
            "Date": Date,
            "String": String,
            "GeographyPoint": String,
            "Double": Float,
            "Binary": LargeBinary
        }
        return {column: datatypes_map[type] for column, type in mapper.items()}


def _get_transforms_used_in(subflight_dict):
    trs = set()
    if type(subflight_dict) is list:
        for v in subflight_dict:
            trs = trs | _get_transforms_used_in(v)
    elif type(subflight_dict) is dict:
        for k, v in subflight_dict.items():
            if "transforms." in k:
                trs.add(k)
            if type(v) is dict or type(v) is list:
                trs = trs | _get_transforms_used_in(v)
    return trs
