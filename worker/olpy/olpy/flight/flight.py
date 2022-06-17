import openlattice
import yaml
import re
from .. import clean, constants, misc
from sqlalchemy.types import *
import pandas as pd
from collections import Counter

from ..clean import atlas


class PropertyDefinition(object):
    """
    A class representing a property definition
    """

    def __init__(self, type = "", column = "", transforms = [], definition_dict = dict(), edm_api = None):
        if not isinstance(definition_dict, dict):
            print("Attempting to automatically interpret %s as a property definition..."%str(definition_dict))
            if isinstance(definition_dict, str):
                self.type = type
                self.column = column
                self.transforms = [
                    {"transforms.ValueTransform":None, "value":definition_dict}
                ]
            elif isinstance(definition_dict, list):
                self.type = type
                self.column = column
                self.transforms = [
                    {"transforms.ConcatTransform":None, "columns":definition_dict, "separator":"-"}
                ]
        else:
            self.type = type if type else (definition_dict['type'] if 'type' in definition_dict.keys() else "")
            self.column = column if column else (definition_dict['column'] if 'column' in definition_dict.keys() else "")

            if "columns" in definition_dict.keys():
                print("Attempting to coerce %s to a ConcatTransform"%str(definition_dict["columns"]))
                self.transforms = [
                    {"transforms.ConcatTransform":None, "columns":definition_dict["columns"], "separator":"-"}
                ]
            elif "value" in definition_dict.keys():
                print("Attempting to coerce %s to a ValueTransform"%str(definition_dict["value"]))
                self.transforms = [
                    {"transforms.ValueTransform":None, "value":definition_dict["value"]}
                ]
            else:
                self.transforms = transforms if transforms else (definition_dict['transforms'] if 'transforms' in definition_dict.keys() else [])
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
            self.property_type = self.edm_api.get_property_type(self.edm_api.get_property_type_id(namespace=fqn[0], name=fqn[1]))
        except openlattice.rest.ApiException as exc:
            self.property_type = openlattice.PropertyType(
                type=openlattice.FullQualifiedName()
            )
    
    def check_datatype_parsers(self, log_level = "none"):
        """
        Validator determines if the appropriate parser is present in the transforms.
        """

        report = clean.report.ValidationReport(
            title = f"Parser Validation for {self.type}",
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")
        datatype = self.get_property_type().datatype if self.get_property_type() else None
        if not datatype:
            report.print_status(log_level = log_level)
            return report
        if datatype:
            if 'Date' in datatype:
                datetimetransforms = re.search(
                    "Date[a-zA-z]*Transform",
                    str(self.transforms))
                timezone_included = "timezone" in str(self.transforms).lower()
                if datetimetransforms is None:
                    report.issues.append(f"No Date(time) parser")
                    report.validated = False
                elif not timezone_included:
                    report.issues.append(f"No timezone")
                    report.validated = False

            elif 'Geography' in datatype:
                parsetransform = re.search(
                    "Geo[a-zA-z]+Transform",
                    str(self.transforms))
                if parsetransform is None:
                    report.issues.append(f"No Geography parser")
                    report.validated = False

            elif 'Boolean' in datatype:
                parsetransform = re.search(
                    "ParseBoolTransform",
                    str(self.transforms))
                if parsetransform is None:
                    report.issues.append(f"No Boolean parser")
                    report.validated = False

            elif not datatype == 'String':
                parsetransform = re.search(
                    "Parse[a-zA-z]+Transform",
                    str(self.transforms))
                if parsetransform is None:
                    report.issues.append(f"No Numeric parser")
                    report.validated = False

        report.validate()
        report.print_status(log_level = log_level)
        return report


    def add_datatype_parser_if_needed(self, timezone = None):
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
                    transform["pattern"] = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.S", "yyyy-MM-dd HH:mm:ss.SS", "yyyy-MM-dd HH:mm:ss.SSS"]
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
        if isinstance(self.transforms, list):
            out['transforms'] = _parse_transforms(self.transforms)
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

    def delete_column(self, column):
        """
        Delete all references to a specific column in this flight

        :return: boolean indicator that the property definition is now empty and should be deleted
        """

        if self.column:
            return self.column == column
        return _delete_column_from_object(self.transforms, column)


class EntityDefinition(object):
    """
    A class representing an entity definition
    """

    def __init__(self, definition_dict = dict(), edm_api = None, entity_sets_api = None):
        self.name = definition_dict['name'] if 'name' in definition_dict.keys() else ""
        self.fqn = definition_dict['fqn'] if 'fqn' in definition_dict.keys() else ""
        self.entity_set_name = definition_dict['entitySetName'] if 'entitySetName' in definition_dict.keys() else ""
        self.conditions = definition_dict['conditions'] if 'conditions' in definition_dict.keys() else []
        self.update_type  = definition_dict['updateType'] if 'updateType' in definition_dict.keys() else "Merge"

        self.edm_api = edm_api
        self.entity_sets_api = entity_sets_api

        self.entity_type = None
        
        # deserialize and check property definitions
        self.property_definitions = {}
        if "propertyDefinitions" in definition_dict.keys():
            for key, defn in definition_dict['propertyDefinitions'].items(): #todo double check removing automatic key-to-type doesn't break anything
                self.property_definitions[key] = PropertyDefinition(definition_dict = defn, edm_api = edm_api)

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

    def add_and_check_edm(self):
        """
        Checks that this instance's property types are included in the EDM for this entity type.
        """

        entity_type = self.get_entity_type()
        sub_reports = []
        for x in self.property_definitions.values():
            if not x.get_property_type().id in entity_type.properties:
                sub_reports.append(
                    clean.report.ValidationReport(
                        report=[f"Property type {x.type} is currently not in entity type {self.fqn}"],
                        validated=False
                    )
                )
            sub_reports.append(
                x.check_datatype_parsers()
            )

        return clean.report.ValidationReport(
            sub_reports = sub_reports,
            validated = True
        )

    def parsers_validation(self, log_level = "none"):
        report = clean.report.ValidationReport(
            title = f"Parsers Validation for Entity Definition {self.name}"
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        for key, defn in self.property_definitions.items():
            sub = defn.check_datatype_parsers(log_level = "none")
            if not sub.validated:
                report.validated = False
                report.issues += [
                    f"In property {key}: {x}" for x in sub.issues
                ]
        report.validate()
        report.print_status(log_level = log_level)
        return report

    def entity_set_validation(self, all_entity_sets = [], already_done = dict(), log_level = "none"):
        report = clean.report.ValidationReport(
            title = f"Entity Set Validation for Entity {self.name}"
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")


        if (self.fqn, self.entity_set_name) in already_done:
            return already_done[(self.fqn, self.entity_set_name)]

        try:
            existing_entity_set = self.entity_sets_api.get_entity_set(self.entity_sets_api.get_entity_set_id(self.entity_set_name))
            if self.get_entity_type().id != existing_entity_set.entity_type_id:
                report.validated = False
                report.issues.append(f"The fqn listed for {self.entity_set_name} does not match that of the existing entity set.")
        except Exception as exc:
            print(exc)
            report.validated = False
            report.issues.append(f"The entity set {self.entity_set_name} doesn't exist.")

        if not report.validated:
            if not all_entity_sets:
                all_entity_sets += self.entity_sets_api.get_all_entity_sets()
            possible_overlap = []
            for entity_set in all_entity_sets:
                if entity_set.entity_type_id == self.get_entity_type().id:
                    count = 0
                    for a, b in zip(list(self.entity_set_name), list(entity_set.name)):
                        if a != b:
                            break
                        count+=1
                    if count >= 3:
                        possible_overlap.append((count, entity_set.name))
            if len(possible_overlap) > 0:
                overlaps = ", ".join([b for a, b in sorted(possible_overlap, reverse = True)])
                report.issues[-1] += f" Did you mean any of these: {overlaps}"

        for sub in report.sub_reports:
            sub.print_status(log_level = log_level)

        report.validate()
        report.print_status(log_level = log_level)
        already_done[(self.fqn, self.entity_set_name)] = report
        return report
        
    def necessary_components_validation(self, log_level = "none"):
        report = clean.report.ValidationReport(
            title = f"Necessary Components Validation for Entity {self.name}"
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        if not self.fqn:
            report.validated = False
            report.issues.append("FQN not defined.")
        if not self.entity_set_name:
            report.validated = False
            report.issues.append("Entity set name not defined.")
        if not self.property_definitions:
            report.validated = False
            report.issues.append("Property definitions not defined.")
        if not self.name:
            report.validated = False
            report.issues.append("Entity definition name not defined.")
        if self.update_type not in {"Merge", "PartialReplace", "Replace"}:
            report.validated = False
            report.issues.append("""Update type not in {"Merge", "PartialReplace", "Replace"}""")
        for key, defn in self.property_definitions.items():
            if not defn.type:
                report.validated = False
                report.issues.append(f"Property definition {key} is missing a type.")
            if not defn.column and not defn.transforms:
                report.validated = False
                report.issues.append(f"In property definition {key}, neither column nor transforms are defined.")
        report.validate()
        report.print_status(log_level = log_level)
        return report

    def fqn_validation(self, log_level = "none"):
        report = clean.report.ValidationReport(
            title = f"FQN Validation for Entity {self.name}"
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")


        entity_type = self.get_entity_type()

        if not entity_type.key:
            report.validated = False
            report.issues.append(f"Entity type {self.fqn} doesn't exist.")

        for x in self.property_definitions.values():
            if not x.get_property_type() or x.get_property_type().id not in entity_type.properties:
                report.validated = False
                report.issues.append(f"Property type {x.type} is currently not in entity type {self.fqn}")
        report.print_status(log_level = log_level)
        return report

    def add_pk_if_missing(self, infer_columns = False, columns = [], hash_by_default = True, suffix = None):
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
            keys = set(["%s.%s"%(pk_type.type.namespace, pk_type.type.name) for pk_type in key_types])

        these = set(self.property_definitions.keys())
        overlap = keys & these
        if len(overlap) == 0:
            pk = keys.pop()
            self.property_definitions[pk] = PropertyDefinition(type = pk, edm_api = self.edm_api)
            if not hash_by_default:
                if len(columns) == 1:
                    self.property_definitions[pk].column = columns[0]
                elif len(columns) > 1:
                    self.property_definitions[pk].transforms = [{"transforms.ConcatTransform":None, "columns":columns}]
            else:
                self.property_definitions[pk].transforms = [{"transforms.HashTransform":None, "columns":columns, "hashFunction":"sha256"}]
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
            pks = set(["%s.%s"%(x.type.namespace, x.type.name) for x in key_types])
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
        if isinstance(self.conditions, list):
            out['conditions'] = _parse_conditions(self.conditions)
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

    def delete_column(self, column):
        """
        Delete all references to a specific column in this entity definition

        :return: boolean indicator that the entity definition now empty and should be deleted
        """

        keys_to_delete = []
        for key, defn in self.property_definitions.items():
            if defn.delete_column(column):
                keys_to_delete.append(key)
        for key in keys_to_delete:
            del self.property_definitions[key]
        _delete_column_from_object(self.conditions, column)

        # consider deletable if primary key definition is gone
        keys = self.get_entity_type().key
        if keys:
            for property in self.property_definitions.values():
                if property.get_property_type().id in keys:
                    return False
            return True
        else:
            # if entity type not in edm, consider deletable iff all property defs are gone
            return not bool(self.get_columns_from_pk())
        

class AssociationDefinition(EntityDefinition):
    """
    A class representing an association definition

    An AssociationDefinition is an EntityDefinition with a defined source and destination.
    """

    def __init__(self, definition_dict = dict(), src_alias = "", dst_alias = "", edm_api = None, entity_sets_api = None):
        super().__init__(definition_dict = definition_dict, edm_api = edm_api, entity_sets_api = entity_sets_api)
        #src and dst are EntityDefinitions unless they aren't defined in the flight, in which case they are set to the src and dst strings given in the definition_dict.
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

    def load_association_type(self, edm = None):
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
                entity_type = openlattice.EntityType(
                    type = openlattice.FullQualifiedName(),
                    key = [],
                    properties = []
                ),
                src = [],
                dst = []
            )
        self.entity_type = self.association_type.entity_type

    def necessary_components_validation(self, log_level = "none"):
        """
        Check association has all necessary components defined.
        """

        report = clean.report.ValidationReport(
            title = f"Necessary Components Validation for Association {self.name}",
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        entity_report = super().necessary_components_validation(log_level = log_level)
        special_report = clean.report.ValidationReport(
            title = f"Source and Destination Defined for Association {self.name}"
        )
        if not self.src_alias:
            special_report.validated = False
            special_report.issues.append("Source not defined.")
        if not self.dst_alias:
            special_report.validated = False
            special_report.issues.append("Destination not defined.")
        special_report.print_status(log_level = log_level)
        report.sub_reports = [entity_report, special_report]
        report.validate()
        report.print_status(log_level = log_level)
        return report
    
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

    def __init__(self, name = "", organization_id = None, configuration=None, path = None):

        self.name = name
        self.entity_definitions = dict()
        self.association_definitions = dict()
        if not configuration:
            self.configuration = misc.get_config()
        else:
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

        out_string = "organizationId: {organization_id}\n".format(organization_id = self.organization_id)
        depth = 2
        for def_type in ['entityDefinitions', 'associationDefinitions']:
            sorted_ent_defs = self._sort_entities_for_writing("entity" if def_type == "entityDefinitions" else "association")
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
                    if prop_defn.transforms:
                        out_string += " " * depth + 'transforms:\n'
                        out_string += _write_trans_conds_list(prop_defn.transforms, "transforms", depth)
                    depth -= 2
                depth -= 2
                if entity.conditions:
                    out_string += " " * depth + 'conditions:\n'
                    out_string += _write_trans_conds_list(entity.conditions, "conditions", depth)
                out_string += " " * depth + 'name: "' + entity.name + '"\n\n'
                depth -=2
        return out_string.replace('\\', "\\\\")

    def _sort_entities_for_writing(self, def_type = 'entity'):
        if def_type == 'entity':
            # sort entities by how well-associated they are
            return sorted(self.entity_definitions.items(),
                         key = lambda pair: sum([1 for x in self.association_definitions.values() if {x.src_alias, x.dst_alias}.intersection({pair[0], pair[1].name})]),
                         reverse = True)
        else:
            # bunch associations by fqn, sorting by trailing integer in the alias
            fqns = set([v.fqn for v in self.association_definitions.values()])
            out = []
            for fqn in fqns:
                out += sorted([x for x in self.association_definitions.items() if x[1].fqn == fqn], key = lambda pair: int("0" + re.search("[0-9]*$", pair[0]).group()))
            return out

    def deserialize(self, filename, organization_id=None):
        """
        Populates this flight's entity and association definitions with a deserialized yaml file
        """

        string = open(filename).read()
        self.deserialize_from_string(string, organization_id)

    def deserialize_from_string(self, string, organization_id):
        """
        Populates this flight's entity and association definitions with a deserialized dictionary string
        """
        
        reformat = "\n".join(string.split("\n"))
        reformat = reformat.replace("!<generators.TransformSeriesGenerator>","")
        reformat = reformat.replace("- !<","- ")
        reformat = reformat.replace(">",":")

        flight_dict = yaml.load(reformat, Loader=yaml.FullLoader)
        if 'organizationId' in flight_dict.keys():
            self.organization_id = flight_dict['organizationId']
        elif organization_id is not None:
            self.organization_id = organization_id
        else:
            raise ValueError("Flights require specification of the organization ID.")

        for key, defn in flight_dict['entityDefinitions'].items():
            self.entity_definitions[key] = EntityDefinition(
                definition_dict = defn,
                edm_api = self.edm_api,
                entity_sets_api = self.entity_sets_api
            )

        for key, defn in flight_dict['associationDefinitions'].items():
            self.association_definitions[key] = AssociationDefinition(
                definition_dict = defn,
                edm_api = self.edm_api,
                entity_sets_api = self.entity_sets_api,
                src_alias = defn["src"],
                dst_alias = defn["dst"]
            )

        self.refresh_schema()
        print("Finished deserializing the flight!")

    
    def deserialize_from_wiki(self, wikistring):
        """
        Deserializes a flight from the shorthand notation commonly found on our wiki pages

        Entity Pattern is supposed to match a block of text with the following format:
        entityname [EntitySetName] (fqn.something)
        - propertyname (fqn.something)

        Association Pattern is supposed to match a block of text with the following format:
        src -> associationname [AssociationEntitySetName] -> dst
        - propertyname (fqn.something)
        
        These patterns are then passed on to make_entity_defn_dict and make_association_defn dict
        to parse out the properties and entities and make it into a dict for regular deserialization
        """

        flight_dict = {'entityDefinitions':{}, 'associationDefinitions':{}}
    
        #match an entity plus its properties and return as list of matches
        entity_pattern = r"((?:^(?:\S+)\s+\[(?:\S+)\]\s+\((?:\S+)\))(?:\n-[^\n]+)+)"
        entity_matches = re.findall(entity_pattern, wikistring, re.MULTILINE)
    
        # for each match, make an entity definition dict
        for entity in entity_matches:
            entity_dict = self.make_entity_defn_dict(entity)
            for k, v in entity_dict.items():
                flight_dict['entityDefinitions'][k] = v

        for key, defn in flight_dict['entityDefinitions'].items():
            self.entity_definitions[key] = EntityDefinition(
                definition_dict = defn,
                edm_api = self.edm_api,
                entity_sets_api = self.entity_sets_api
            )

   
        #make associations
        association_pattern = r"((?:\S+)\s+(?:->|→|-->)\s+(?:\S+)\s+\[(?:\S+)\]\s+\((?:\S+)\)\s+(?:->|→|-->)\s+(?:\S+)(?:(?:\n-[^\n]+)+)?)"
        association_matches = re.findall(association_pattern, wikistring, re.MULTILINE)
        
        for association in association_matches:
            association_dict = self.make_association_defn_dict(association)
            for k, v in association_dict.items():
                flight_dict['associationDefinitions'][k] = v
    

    
        for key, defn in flight_dict['associationDefinitions'].items():
            self.association_definitions[key] = AssociationDefinition(
                definition_dict = defn,
                edm_api = self.edm_api,
                entity_sets_api = self.entity_sets_api,
                src_alias = defn["src"],
                dst_alias = defn["dst"]
            )
    
        self.refresh_schema()

    
        print("Deserialized from wikistring")


    def make_entity_defn_dict(self, entpropstring):
        
        #make properties
        p_dict = {}
        p_pattern = r"-\s+(\S+)\s+\((\S+)\)"
        p_matches = re.findall(p_pattern, entpropstring, re.MULTILINE)
        for match in p_matches:
            
            p_dict[match[1]] = {"column":match[0], "type":match[1]}
            
        #make entities   
        e_pattern = r"^(\S+)\s+\[(\S+)\]\s+\((\S+)\)"
        e_match = re.match(e_pattern, entpropstring)
        e_dict = {e_match[1]:{}}

        e_dict[e_match[1]]['name'] = e_match[1]
        e_dict[e_match[1]]['entitySetName'] = e_match[2] 
        e_dict[e_match[1]]['fqn'] = e_match[3]
        e_dict[e_match[1]]['propertyDefinitions'] = p_dict   

         
                  
        return e_dict

    def make_association_defn_dict(self, assnpropstring):
        
        #make properties
        p_dict = {}
        p_pattern = r"-\s+(\S+)\s+\((\S+)\)"
        p_matches = re.findall(p_pattern, assnpropstring, re.MULTILINE)
        for match in p_matches:
            
            p_dict[match[1]] = {"column":match[0], "type":match[1]}
            
        #make associations   
        assn_pattern = r"(\S+)\s+(?:->|→|-->)\s+(\S+)\s+\[(\S+)\]\s+\((\S+)\)\s+(?:->|→|-->)\s+(\S+)"
        assn_match = re.match(assn_pattern, assnpropstring)
        assn_dict = {assn_match[2]:{}}

        assn_dict[assn_match[2]]['src'] = assn_match[1]
        assn_dict[assn_match[2]]['name'] = assn_match[2]
        assn_dict[assn_match[2]]['entitySetName'] = assn_match[3] 
        assn_dict[assn_match[2]]['fqn'] = assn_match[4]
        assn_dict[assn_match[2]]['dst'] = assn_match[5]
        assn_dict[assn_match[2]]['propertyDefinitions'] = p_dict  

                  
        return assn_dict

    @property
    def wiki(self):
        """
        Produces a string representation of the flight using shorthand suitable for the wiki
        """

        for defn in ['entityDefinitions', 'associationDefinitions']:

            for ent in self.schema[defn].keys():
                if defn == 'associationDefinitions':
                    print(f"{self.schema[defn][ent]['src']} -> "\
                    +f"{self.schema[defn][ent]['name']} "\
                    +f"[{self.schema[defn][ent]['entity_set_name']}]"
                    +f"({self.schema[defn][ent]['fqn']}) -> "\
                    +f"{self.schema[defn][ent]['dst']}")
                else:
                    print(f"{ent} [{self.schema[defn][ent]['entity_set_name']}] ({self.schema[defn][ent]['fqn']})")
                for prop in self.schema[defn][ent]['properties']:
                    print(f"- {prop['column']} ({prop['fqn']})")

    def refresh_schema(self):
        """
        Refreshes the schema instance variable with the latest changes made to the flight.
        """

        self.schema = {
            "entityDefinitions": {key: defn.get_schema() for key, defn in self.entity_definitions.items()},
            "associationDefinitions": {key: defn.get_schema() for key, defn in self.association_definitions.items()}
        }

        for defn_type in ["entityDefinitions", "associationDefinitions"]:
            for defn in self.schema[defn_type].values():
                defn["flight"] = self.name

    def delete_column(self, column):
        """
        Delete all references to a specific column in this flight

        :return: boolean indicator that the flight is now empty
        """

        keys_to_delete = []
        for key, defn in self.entity_definitions.items():
            if defn.delete_column(column):
                keys_to_delete.append(key)
        for key in keys_to_delete:
            self.delete_entity_definition(key)
        keys_to_delete = []
        for key, defn in self.association_definitions.items():
            if defn.delete_column(column):
                keys_to_delete.append(key)
        for key in keys_to_delete:
            del self.association_definitions[key]
        return not bool(self.entity_definitions)

    def delete_entity_definition(self, name):
        real_name = name
        if name in self.entity_definitions.keys():
            if self.entity_definitions[name].name:
                real_name = self.entity_definitions[name].name
            del self.entity_definitions[name]
        else:
            to_delete = None
            for alias, defn in self.entity_definitions.items():
                if defn.name == name:
                    to_delete = alias
            if to_delete:
                del self.entity_definitions[to_delete]

        # delete association definitions connected to this entity definition
        to_delete = []
        for alias, defn in self.association_definitions.items():
            if defn.src_alias == real_name or defn.dst_alias == real_name or alias == name or defn.name == name:
                to_delete.append(alias)

        for alias in to_delete:
            del self.association_definitions[alias]

    def add_and_check_edm(self):

        """
        Quick check against the EDM of property types, sources, and destinations

        This function is called within Flight.proofread
        """
        reports = []
        print("Checking property types for association types...")
        reports += [x.add_and_check_edm() for x in self.association_definitions.values()]
        print("Checking property types for entity types...")
        reports += [x.add_and_check_edm() for x in self.entity_definitions.values()]

        report = clean.report.ValidationReport(
            title = "EDM Validation",
            sub_reports = [
                clean.report.ValidationReport(
                    title="Check if property types have appropriate parsers",
                    sub_reports = reports,
                    validated = True
                ),
                self.check_edges_edm()
            ]
        )

        return report


    def transform_schema(self, type="fqn"):
        '''
        Reduce the flight by fqn/entityset/...
        Mainly for visualisation purposes to be used in visuals
        '''

        # initiate reduced schema
        reduced_schema = {"nodes": {}, "edges": {}}

        # nodes
        for entity in self.schema['entityDefinitions'].values():
            if not entity[type] in reduced_schema['nodes'].keys():
                reduced_schema['nodes'][entity[type]] = {"objects": [entity]}
            else:
                reduced_schema['nodes'][entity[type]]['objects'] += [entity]

        # edges
        for association in self.schema['associationDefinitions'].values():

            src = association['src']
            dst = association['dst']
            entsrcs = [x for x in self.schema['entityDefinitions'].values() if x['name'] == src]
            entdsts = [x for x in self.schema['entityDefinitions'].values() if x['name'] == dst]

            if not (len(entdsts) == 1 and len(entsrcs) == 1):
                raise ValueError("  - The source and destination for association \n    %s are not (uniquely) defined."%association['name'])

            edge = (entsrcs[0][type], entdsts[0][type])

            if not association[type] in reduced_schema['edges'].keys():
                    reduced_schema['edges'][association[type]] = {
                    "objects": [association],
                    "edges": [edge]}
            else:
                reduced_schema['edges'][association[type]]['objects'] += [association]
                if not edge in reduced_schema['edges'][association[type]]['edges']:
                    reduced_schema['edges'][association[type]]['edges'] += [edge]
        return reduced_schema

    def check_entsets_against_stack(self, create_by = []):
        """
        Checks entity sets for existence, fqn alignment, and potential inadvertent renaming
        """

        report = clean.report.ValidationReport(
            title = "Entity Set Validation",
            validated = True
        )

        sub_reports = {
            "dont_exist": clean.report.ValidationReport(
                title="Check if entity sets exist",
                validated=False
            ),
            "fqn_match": clean.report.ValidationReport(
                title="Check if FQN match between OL and the flight",
                validated=False
            ),
            "possible_overlap": clean.report.ValidationReport(
                title="Check if there are entity sets on OL that might be targeted",
                issues = [],
                validated=True
            )
        }

        if len(create_by) > 0:
            sub_reports['created'] = clean.report.ValidationReport(
                title="Check if there are entity sets that need to be created",
                issues = [],
                validated=True
            )


        entsets = self.entity_sets_api.get_all_entity_sets()
        done = set()
        for entity in list(self.entity_definitions.values()) + list(self.association_definitions.values()):
            if entity.entity_set_name in done:
                continue
            done.add(entity.entity_set_name)
            try:
                prod_entset = self.entity_sets_api.get_entity_set(self.entity_sets_api.get_entity_set_id(entity.entity_set_name))
                if entity.get_entity_type().id != prod_entset.entity_type_id:
                    sub_reports['fqn_match'].issues += [f"The entity type of {entity.entity_set_name} does not match the existing entity set."]
            except:
                if len(create_by)>0:
                    try:
                        entset_to_create = openlattice.EntitySet(
                                        name=entity.entity_set_name,
                                        title=entity.entity_set_name,
                                        entity_type_id = entity.get_entity_type().id,
                                        organization_id=self.organization_id,
                                        contacts=create_by
                        )
                        self.entity_sets_api.create_entity_sets([entset_to_create])
                        sub_reports['created'].issues += [f"Created entity set {entity.entity_set_name}."]
                    except openlattice.exceptions.ApiException as e:
                        sub_reports['created'].issues += [f"Couldn't create entity set {entity.entity_set_name}: {e}"]
                        sub_reports['created'].validated = False
                else:
                    sub_reports['dont_exist'].issues += [f"The entity set {entity.entity_set_name} doesn't exist."]

            possible_overlap = []
            for entset in entsets:
                if entset.entity_type_id == entity.entity_type.id and entset.name != entity.entity_set_name:
                    count = 0
                    for a, b in zip(list(entity.entity_set_name), list(entset.name)):
                        if a != b:
                            break
                        count+=1
                    if count >= 3:
                        possible_overlap.append((count, entset.name))
            if len(possible_overlap) > 0:
                overlaps = ", ".join([b for a, b in sorted(possible_overlap, reverse = True)])
                toadd = [f"For {entity.entity_set_name}, did you mean any from: {overlaps}"]
                sub_reports['possible_overlap'].issues += toadd

        if len(sub_reports['dont_exist'].issues) == 0:
            sub_reports['dont_exist'].issues = ["All entity sets exist! Yay!"]
            sub_reports['dont_exist'].validated = True
        if len(sub_reports['fqn_match'].issues) == 0:
            sub_reports['fqn_match'].issues = ["No fqn mismatch! Hot diggity!"]
            sub_reports['fqn_match'].validated = True
        if len(sub_reports['possible_overlap'].issues) == 0:
            sub_reports['possible_overlap'].issues = ["No potential overlaps between entity sets."]

        report.sub_reports = list(sub_reports.values())

        return report

    ##################################################

    def proofread(self, table_columns = None, authenticated = True, create_by = []):
        """
        Thoroughly proofreads a flight
        """

        report = clean.report.ValidationReport(
                title="Proofreading the flight",
                issues = []
            )

        report.sub_reports = [self.add_and_check_edm()]

        if authenticated:
            print("\nChecking entity sets against the stack")
            report.sub_reports += [self.check_entsets_against_stack(create_by = create_by)]
        else:
            report.sub_reports += [clean.report.ValidationReport(
                title="Couldn't check entity sets against the stack.",
                issues = [],
                validated=False
            )]

        print("\nChecking entities and properties named consistently...")
        badness = False
        for ent_alias, ent in list(self.entity_definitions.items()) + list(self.association_definitions.items()):
            if ent_alias != ent.name:
                print("Entity alias '" + ent_alias + "' doesn't match its name '" + ent.name + "'.")
                badness = True
            for prop_alias, prop in ent.property_definitions.items():
                if prop_alias != prop.type:
                    print("Property alias '" + prop_alias + "' doesn't match its type '" + prop.type + "'.")
                    badness = True
        if not badness:
            print("Naming is consistent! Huzzah!")

        print("\nChecking graph connectivity...")

        src_dst = set([x.src_alias for x in self.association_definitions.values()] + [x.dst_alias for x in self.association_definitions.values()])
        entity_names = set([v.name if v.name else k for k, v in self.entity_definitions.items()])
        missing_entities = src_dst - entity_names
        missing_associations = entity_names - src_dst

        if len(missing_associations)>0:
            print("The following entity sets are not linked to anything: %s"%", ".join(missing_associations))
        if len(missing_entities)>0:
            print("The following entity sets are not correctly referenced in their association: %s"%", ".join(missing_entities))
        if len(missing_associations) + len(missing_entities) == 0:
            print("No unattached entities or associations :)")

        print("\nChecking association src and dst in EDM")
        assoc_src_dsts = set()
        dup_assocs = set()
        badness = False
        for assoc_def in self.association_definitions.values():
            # log duplicates
            asd = (assoc_def.fqn, assoc_def.src_alias, assoc_def.dst_alias)
            if asd in assoc_src_dsts:
                dup_assocs.add(asd)
            else:
                assoc_src_dsts.add(asd)
            assoc_type = assoc_def.get_association_type()
            src_def = self.entity_definitions[assoc_def.src_alias] if assoc_def.src_alias in self.entity_definitions else [x for x in self.entity_definitions.values() if x.name and x.name == assoc_def.src_alias]
            dst_def = self.entity_definitions[assoc_def.dst_alias] if assoc_def.dst_alias in self.entity_definitions else [x for x in self.entity_definitions.values() if x.name and x.name == assoc_def.dst_alias]
            if isinstance(src_def, list):
                src_def = src_def[0]
            if isinstance(dst_def, list):
                dst_def = dst_def[0]
            if assoc_type:
                if src_def.get_entity_type().id not in assoc_type.src:
                    badness = True
                    print(assoc_def.fqn + " doesn't have " + src_def.fqn + " in its sources.")
                if dst_def.get_entity_type().id not in assoc_type.dst:
                    badness = True
                    print(assoc_def.fqn + " doesn't have " + dst_def.fqn + " in its destinations.")
            else:
                print("mrrrrrr")
        if not badness:
            print("Sources and destinations are fine! Whoop whoop!")

        print("\nChecking for duplicate association definitions")
        if len(dup_assocs) > 0:
            print("There are multiple associations for each of these (fqn, src, dst): " + str(dup_assocs))
        else:
            print("No duplicate associations! Hurray!")

        if authenticated:
            print("\nChecking entity sets against the stack")
            stack_check = self.check_entsets_against_stack()

            if stack_check["don't exist"]:
                print("These entity sets don't exist:\n%s\n"%("\n".join(stack_check["don't exist"])))
            else:
                print("All entity sets exist! Yay!")

            if stack_check["fqn mismatch"]:
                print("These entity sets exist, but have a different fqn:\n%s\n"%("\n".join(stack_check["fqn mismatch"])))
            else:
                print("No fqn mismatch! Hot diggity!")

            if stack_check["possible overlap"]:
                for entset, possible_overlap in stack_check["possible overlap"].items():
                    print(entset + " might be related to " + ", ".join(possible_overlap))

        print("\nChecking person datasources")

        datasources_acounted_for = True
        for entity in self.entity_definitions.values():
            if entity.fqn == "general.person":
                badness = True
                for prop in entity.property_definitions.values():
                    if prop.type == "ol.datasource":
                        badness = False
                        break
                if badness:
                    print("Entity %s needs a datasource."%entity.name)
                    datasources_acounted_for = False

        if datasources_acounted_for:
            print("Datasources accounted for! Oh joy!")

        if table_columns is not None:
            print("\nChecking columns")
            used = self.get_all_columns()
            bad_cols = list(used - set(table_columns))
            unused = list(set(table_columns) - used)
            if len(bad_cols) > 0:
                print("These columns don't exist:\n  " + str(bad_cols))
            else:
                print("All used columns exist! Callooh! Callay!")
            print("\n" + str(len(used)) + " columns used: " + str(list(used)))
            print(str("\n" + str(len(unused))) + " columns not used: " + str(list(unused)))

        return report

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
        for ent in list(self.entity_definitions.values())+list(self.association_definitions.values()):
            if not ent.entity_set_name in checker.keys():
                checker[ent.entity_set_name] = ent.fqn
                entset = {
                    "entity_type_id": ent.get_entity_type().id,
                    "name": ent.entity_set_name,
                    "title": "%s%s%s"%(add_prefix,ent.entity_set_name.replace(remove_prefix,""), add_suffix),
                    "contacts": contacts
                }
                out.append(entset)
            else:
                if not checker[ent.entity_set_name] == ent.fqn:
                    raise ValueError("%s is registered for different fqn's !"%ent.entity_set_name)
        return out

    def get_entity(self, keyword, type='fqn'):
        """
        Gets all entity definitions that match keyword
        """

        out = list([x for x in self.entity_definitions.values() if x.__dict__[type] == keyword])
        if len(out) == 1:
            return out[0]
        else:
            return out

    def get_datatypes(self):
        """
        Returns a dict of fqn: datatype pairs present in this flight.
        """

        # if not hasattr(self.entity_definitions[0].property_definitions[0], '_property_type_id'):
        #     self.add_and_check_edm()
        datatypes = {}
        for ent in list(self.entity_definitions.values())+list(self.association_definitions.values()):
            for propertydef in ent.property_definitions.values():
                datatypes[propertydef.type] = propertydef.get_property_type().datatype
        return datatypes

    def get_datatypes_by_column(self):
        """
        Returns a dict of column: datatype pairs present in this flight.
        """

        entities = list(self.entity_definitions.values())+list(self.association_definitions.values())
        datatypes = [
            {"column": propertydef.column, "datatype": propertydef.get_property_type().datatype} \
            for ent \
            in entities \
            for propertydef \
            in ent.property_definitions.values()
        ]
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

    def get_atlas_engine_for_organization(self):
        '''
        Gets the organization engine
        '''
        engine = atlas.get_atlas_engine_for_organization(self.organization_id, self.configuration)
        return engine

    def get_atlas_engine_for_individual_user(self):
        '''
        Gets the organization engine
        '''
        engine = atlas.get_atlas_engine_for_individual_user(self.organization_id, self.configuration)
        return engine

    def validate_flight_against_atlas(self, table_name = None, engine = None, log_level = "none"):
        '''
        Validates the flight with a table on atlas

        :param table_name: name of the table to accompany the flight
        :param engine: sqlalchemy.Engine
        :return: dict with parameters "validated" (True/False) and "report" which contains the report
        '''

        report = clean.report.ValidationReport(
            title = "Atlas Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        if not table_name:
            report.validated = False
            report.issues.append("No table name given.")
            report.print_status(log_level = log_level)
            return report

        if not engine:
            engine = self.get_atlas_engine_for_organization()

        # current datatypes of the atlas table
        type_is = clean.atlas.get_datatypes(table_name, engine) \
            .rename(columns={"data_type": "postgres_data_type"})

        table_exists_report = clean.report.ValidationReport(
            title="Check if table exists."
        )

        report.sub_reports.append(table_exists_report)

        if type_is.shape[0] == 0:
            table_exists_report.validated = False
            table_exists_report.issues.append("The atlas table does not exist !")
            table_exists_report.print_status(log_level = log_level)
            report.validate()
            report.print_status(log_level = log_level)
            return report

        table_exists_report.print_status(log_level = log_level)

        # data type the columns should be
        flight_types = self.get_datatypes_by_column()
        type_should_java = pd.DataFrame([
            {"column": k, "ol_data_type": v} for k, v in flight_types.items()])

        # linkage between postgres and open lattice
        ol_to_postgres = [
            {"ol_data_type": oltype, "postgres_data_type": pstype} \
            for oltype, pstypes in constants.datatypes.POSTGRES_TO_OL.items() for pstype in pstypes]
        ol_to_postgres = pd.DataFrame(ol_to_postgres)
        type_should = type_should_java.merge(
            ol_to_postgres,
            how='left',
            on='ol_data_type'
        ).set_index('column')

        # check for missing columns
        missing_columns_report = clean.report.ValidationReport(
            title = "Missing columns"
        )
        report.sub_reports.append(missing_columns_report)

        missing_columns = list(set(type_should.index) - set(type_is.index))
        if len(missing_columns) > 0:
            missing_columns_report.validated = False
            missing_columns_report.issues.append("The following columns are missing from the table: %s\n" % ", ".join(missing_columns))

        missing_columns_report.print_status(log_level = log_level)

        # compare data types
        all_cols = list(self.get_all_columns() - set(missing_columns))
        mismatches = []
        for column in all_cols:
            current_type = type_is.loc[column].postgres_data_type
            required_types = type_should.loc[column].postgres_data_type
            if isinstance(type_should.loc[column].postgres_data_type, pd.Series):
                required_types = list(required_types)
            else:
                required_types = [required_types]
            match = current_type in required_types
            if not match:
                mismatches += """
                    Data type mismatch:
                    column "{column}" is of type "{atlas_type} "
                    but should be: "{prod_type}"
                    """.format(
                    column=column,
                    atlas_type=current_type,
                    prod_type=", ".join(required_types)
                )
        datatype_report = clean.report.ValidationReport(
            title="Mismatching data types",
        )
        report.sub_reports.append(datatype_report)
        if len(mismatches) > 0:
            datatype_report.validated = False
            datatype_report.issues = mismatches

        datatype_report.print_status(log_level = log_level)
        report.validate()
        report.print_status(log_level = log_level)
        return report

    def source_destination_validation(self, log_level = "none"):
        """
        Determines whether sources and destinations are in the EDM
        """

        report = clean.report.ValidationReport(
            title = "Source and Destination Validation" + (f" for Flight {self.name}" if self.name else ""),
            issues = ["Consider calling flight.add_src_dst_to_edm() with the current flight instance."] #issues are only shown if validated == False
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        for assoc_def in self.association_definitions.values():
            assoc_type = assoc_def.get_association_type()
            src_def = self.get_entity_definition_by_name(assoc_def.src_alias)
            dst_def = self.get_entity_definition_by_name(assoc_def.dst_alias)
            if not src_def:
                report.validated = False
                report.issues.append(f"Source entity {assoc_def.src_alias} doesn't exist.")
            if not dst_def:
                report.validated = False
                report.issues.append(f"Destination entity {assoc_def.dst_alias} doesn't exist.")
            if src_def and dst_def and assoc_type:
                if src_def.get_entity_type().id not in assoc_type.src:
                    report.validated = False
                    report.issues.append(f"{assoc_def.fqn} doesn't have {src_def.fqn} in its sources.")
                if dst_def.get_entity_type().id not in assoc_type.dst:
                    report.validated = False
                    report.issues.append(f"{assoc_def.fqn} doesn't have {dst_def.fqn} in its sources.")


        report.validate()
        report.print_status(log_level = log_level)
        return report


    def edm_validation(self, log_level = "none"):
        """
        Determines if all fqns exist in the EDM.
        """

        report = clean.report.ValidationReport(
            title = "EDM Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        for key, defn in list(self.entity_definitions.items()) + list(self.association_definitions.items()):
            fqn_validation = defn.fqn_validation(
                log_level = "none"    # no logs on purpose -- clean logs printed later
            )
            if not fqn_validation.validated:
                report.validated = False
                report.issues += [f"In entity definition {key}: {x}" for x in fqn_validation.issues]


        src_dst = self.source_destination_validation(log_level = log_level)

        report.sub_reports.append(src_dst)

        report.validate()
        report.print_status(log_level = log_level)
        return report


    def parsers_validation(self, log_level = "none"):
        """
        Determines whether appropriate parsers are included
        """

        report = clean.report.ValidationReport(
            title = "Parsers Validation" + (f" for Flight {self.name}" if self.name else "")
        )
        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        for key, defn in list(self.entity_definitions.items()) + list(self.association_definitions.items()):
            validation = defn.parsers_validation(
                log_level = "none"
            )
            if not validation.validated:
                report.validated = False
                report.issues += [f"In entity definition {key}: {x}" for x in validation.issues]

        report.validate()
        report.print_status(log_level = log_level)
        return report



    def datatypes_validation(self, log_level = "none"):
        """
        Determines whether all property definitions are writing the proper datatype.
        """

        # TODO combine parsers_validation with validate_flight_against_atlas

        print("Datatypes validation check is not implemented yet! Checking a stricter condition: parsers validation")

        return self.parsers_validation(log_level = log_level)


    def datetimetransform_timezone_validation(self, log_level = "none"):
        """
        timezone in Datatimetransform is broken. This checks if it's being used.
        """

        report = clean.report.ValidationReport(
            title = "DatetimeTransform Time Zone Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        for key, defn in list(self.entity_definitions.items()) + list(self.association_definitions.items()):
            for alias, prop in defn.property_definitions.items():
                tf = str(prop.transforms)
                if re.search("Date[a-zA-Z]*Transform", tf) and "timezone" in tf:
                    report.validated = False
                    report.issues.append(f"In {key}, {alias} is using a Date*Transform with timezone argument. This is deprecated and will not have the desired behavior.")
        report.validate()
        report.print_status(log_level = log_level)
        return report



    def entity_sets_validation(self, log_level = "none"):
        """
        Determines whether all entity sets exist and have the FQNs specified in this flight.
        """

        report = clean.report.ValidationReport(
            title = "Entity Sets Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")
        all_entity_sets = self.entity_sets_api.get_all_entity_sets() #todo record this for global access
        already_done = dict()
        subs = [
            defn.entity_set_validation(
                log_level = "none",    # no logs on purpose -- clean logs printed later
                all_entity_sets = all_entity_sets,
                already_done = already_done
            ) for defn in list(self.entity_definitions.values()) + list(self.association_definitions.values())
        ]

        invalids = [sub for sub in subs if not sub.validated]

        if invalids:
            report.validated = False
            report.issues = sum([sub.issues for sub in invalids], [])
        
        report.validate()
        report.print_status(log_level = log_level)
        return report
        

    def necessary_components_validation(self, log_level = "none"):
        """
        Determines whether all required components of this flight's entity/association definitions are defined.

        log_level can be "all", "all_results", "only_failures", or "none".
        """

        report = clean.report.ValidationReport(
            title = "Necessary Components Defined Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        if self.organization_id is None or self.organization_id == "":
            report.validated = False
            report.issues.append("Add missing organizationId.")
        if not self.entity_definitions:
            report.validated = False
            report.issues.append("This flight has no entity definitions.")


        for key, defn in list(self.entity_definitions.items()) + list(self.association_definitions.items()):
            entity_validation = defn.necessary_components_validation(
                log_level = "none" # no logs on purpose -- clean logs printed later
            )
            if not entity_validation.validated:
                report.validated = False
                report.issues += [f"In entity definition {key}: {x}" for x in entity_validation.issues]
        
        report.validate()
        report.print_status(log_level = log_level)
        return report


    def unique_names_validation(self, log_level = "none"):
        """
        Determines if a flight's entity/association definitions have unique names.

        log_level can be "all", "failures", or "none".
        """

        report = clean.report.ValidationReport(
            title = "Unique Names Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        accounted_for = set()
        for defn in list(self.entity_definitions.values()) + list(self.association_definitions.values()):
            if str(defn.name) in accounted_for:
                report.validated = False
                report.issues.append(f"There are many entity/association definitions with name {str(defn.name)}.")
            accounted_for.add(str(defn.name))

        report.validate()
        report.print_status(log_level = log_level)
        return report

    def final_pre_launch_validation(self, table_name = None, engine = None, log_level = "none"):
        """
        Determines whether a given flight is ready for a shuttle run.

        log_level can be "all", "failures", or "none".
        """

        report = clean.report.ValidationReport(
            title = "Final Pre-launch Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        report.sub_reports = [
            self.edm_validation(log_level = log_level),
            self.validate_flight_against_atlas(table_name = table_name, engine = engine, log_level = log_level),
            self.entity_sets_validation(log_level = log_level),
            self.necessary_components_validation(log_level = log_level),
            self.unique_names_validation(log_level = log_level),
            self.datatypes_validation(log_level = log_level),
            self.datetimetransform_timezone_validation(log_level = log_level)
        ]
        report.validate()
        report.print_status(log_level = log_level)
        return report

    def graph_connectivity_validation(self, log_level = "none"):
        """
        Determines whether all entities are linked by at least one association
        """

        report = clean.report.ValidationReport(
            title = "Graph Connectivity" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        src_dst = set([x.src_alias for x in self.association_definitions.values()] + [x.dst_alias for x in self.association_definitions.values()])
        entity_names = set([v.name if v.name else k for k, v in self.entity_definitions.items()])
        missing_associations = entity_names - src_dst

        if len(missing_associations)>0:
            report.validated = False
            report.issues.append("The following entity sets are not linked to anything: %s"%", ".join(missing_associations))

        report.validate()
        report.print_status(log_level = log_level)
        return report

    def consistent_names_validation(self, log_level = "none"):
        report = clean.report.ValidationReport(
            title = "Double Check Name Inconsistencies" + (f" in Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")

        badness = False

        for ent_alias, ent in list(self.entity_definitions.items()) + list(self.association_definitions.items()):
            if ent_alias != ent.name:
                report.validated = False
                report.issues.append(f"Entity alias '{ent_alias}' doesn't match its name '{ent.name}'.")
            for prop_alias, prop in ent.property_definitions.items():
                if prop_alias != prop.type:
                    report.validated = False
                    report.issues.append(f"Property alias '{prop_alias}' doesn't match its type '{prop.type}'.")
        report.validate()
        report.print_status(log_level = log_level)
        return report

    def datasource_validation(self, log_level = "none"):
        report = clean.report.ValidationReport(
            title = "Datasource Validation" + (f" for Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")
        
        for entity in self.entity_definitions.values():
            if entity.fqn == "general.person":
                badness = True
                for prop in entity.property_definitions.values():
                    if prop.type == "ol.datasource":
                        badness = False
                        break
                if badness:
                    report.validated = False
                    report.issues.append(f"Entity definition {entity.name} needs a datasource.")

        report.validate()
        report.print_status(log_level = log_level)
        return report

    def red_flags_validation(self, log_level = "none"):
        report = clean.report.ValidationReport(
            title = "Misc. Red Flags that Aren't Necessarily Errors" + (f" in Flight {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")


        report.sub_reports = [
            self.graph_connectivity_validation(log_level = log_level),
            self.consistent_names_validation(log_level = log_level),
            self.datasource_validation(log_level = log_level)
        ]

        report.validate()
        report.print_status(log_level = log_level)
        return report
        

    def flight_validation(self, table_name = None, engine = None, log_level = "none"):

        report = clean.report.ValidationReport(
            title = "Flight Validation" + (f" for {self.name}" if self.name else "")
        )

        # if log_level == "all":
        #     print(f"Starting on {report.title}")


        report.sub_reports = [
            self.final_pre_launch_validation(table_name = None, engine = None, log_level = log_level),
            self.red_flags_validation(log_level = log_level)
        ]

        report.validate()
        report.print_status(log_level = log_level)
        return report



    def check_edges_edm(self):
        """
        Checks association definitions for missing source/destination objects or disallowed source/destination fqns
        """

        report = clean.report.ValidationReport(
            title = "Edges validation"
        )

        sub_reports = {
            "entitysets" :clean.report.ValidationReport(
                title="Check if sources and destinations are defined",
                issues=[],
                validated=False
            ),
            "edm violation": clean.report.ValidationReport(
                title="Check if sources and destinations are allowed in the EDM",
                issues=[],
                validated=False
            ),
            "duplicate associations": clean.report.ValidationReport(
                title = "Check if edges are uniquely defined",
                issues = [],
                validated = True
            )
        }

        assoc_src_dsts = set()
        for edge_obj in self.association_definitions.values():

            asd = (edge_obj.fqn, edge_obj.src_alias, edge_obj.dst_alias)
            if not asd in assoc_src_dsts:
                assoc_src_dsts.add(asd)
            else:
                sub_reports['duplicate associations'].issues += [f"There are multiple associations to wire" + \
                                                    f"{asd[0]} --> {asd[1]} --> {asd[2]}"]

            src_obj = self.get_entity_definition_by_name(edge_obj.src_alias)

            if not src_obj:
                sub_reports['entitysets'].issues += [f"Unknown source entity set {edge_obj.src_alias} for "% + \
                                                    f"Association {edge_obj.name}"]
            else:
                if not src_obj.get_entity_type().id not in edge_obj.get_association_type().src:
                    sub_reports['edm violation'].issues += [f"Entity type {src_obj.fqn} is not a source for " + \
                                                           f"Association type {edge_obj.fqn}"]

            dst_obj = self.get_entity_definition_by_name(edge_obj.dst_alias)
            if not dst_obj:
                sub_reports['entitysets'].issues += [f"Unknown destination entity set {edge_obj.dst_alias} for " + \
                                                    f"Association {edge_obj.name}"]
            else:
                if not dst_obj.get_entity_type().id not in edge_obj.get_association_type().dst:

                    sub_reports['edm violation'].issues += [f"Entity type {dst_obj.fqn} is not a destination for " + \
                                                           f"Association type {edge_obj.fqn}"]

        if len(sub_reports['entitysets'].issues) == 0:
            sub_reports['entitysets'].issues = ["All sources and destinations are defined.  Good job !"]
            sub_reports['entitysets'].validated = True
        if len(sub_reports['edm violation'].issues) == 0:
            sub_reports['edm violation'].issues = ["All sources and destinations are defined in the EDM. Whoop whoop !"]
            sub_reports['edm violation'].validated = True
        if len(sub_reports['duplicate associations'].issues) == 0:
            sub_reports['duplicate associations'].issues = ["No duplicate associations! Hurray!"]

        report.sub_reports = list(sub_reports.values())

        return(report)


    def add_src_dst_to_edm(self):
        for assoc_def in self.association_definitions.values():
            assoc_type = assoc_def.get_association_type()
            src_def = self.get_entity_definition_by_name(assoc_def.src_alias)
            dst_def = self.get_entity_definition_by_name(assoc_def.dst_alias)
            if assoc_type:
                if src_def.get_entity_type().id not in assoc_type.src:
                    self.edm_api.add_src_entity_type_to_association_type(assoc_type.entity_type.id, src_def.get_entity_type().id)
                    print(assoc_def.fqn, src_def.fqn)
                if dst_def.get_entity_type().id not in assoc_type.dst:
                    self.edm_api.add_dst_entity_type_to_association_type(assoc_type.entity_type.id, dst_def.get_entity_type().id)
                    print(assoc_def.fqn, dst_def.fqn)



    def fill_in(
        self,
        create_entity_fqns = True,
        create_entity_names = True,
        create_entity_set_names = True,
        jurisdiction_string = "",

        gen_missing_pks = True,
        infer_pk_cols = True,
        default_pk_cols = [],
        hash_by_default = True,

        add_conditions = False,

        make_parsers = True,
        timezone = None,
 
    ):
        """
        Intelligently fills in omitted redundancies in the flight.
        """

        all_entity_types = self.edm_api.get_all_entity_types()
        all_property_types = self.edm_api.get_all_property_types()

        new_ent_names = dict()
        for alias, entity in list(self.entity_definitions.items()) + list(self.association_definitions.items()):

            name_words = alias.split(" ")

            if len(name_words) > 1:
                new_alias = "".join(name_words)
                new_ent_names[alias] = new_alias
                alias = new_alias

            #create entitySetName
            if not entity.entity_set_name and create_entity_set_names:
                entity.entity_set_name = jurisdiction_string + "".join([re.sub("[0-9]+", "", word.capitalize()) for word in name_words])

            # create fqn
            if not entity.fqn and create_entity_fqns:
                entity.fqn = ".".join(deduce_edm_object(alias, from_pool = all_entity_types))

            # add entity names
            if create_entity_names:
                if entity.name:
                    if entity.name != alias:
                        print("Entity alias '" + alias + "' doesn't match its name '" + entity.name + "'")
                else:
                    entity.name = alias

            # replace "pk" with actual pk property type
            if "pk" in entity.property_definitions.keys():
                pks = entity.get_entity_type().key
                if pks:
                    pk_type = self.edm_api.get_property_type(pks[0])
                    pk = "%s.%s"%(pk_type.type.namespace, pk_type.type.name)
                else:
                    pk = "ol.id"
                entity.property_definitions[pk] = entity.property_definitions["pk"]
                entity.property_definitions[pk].type = pk
                del entity.property_definitions["pk"]

            for prop_alias, property in entity.property_definitions.items():
                #deduce property fqn from alias
                if not property.type:
                    property.type = ".".join(deduce_edm_object(prop_alias, from_pool = all_property_types))

        for alias, new_alias in new_ent_names.items():
            if alias in self.entity_definitions.keys():
                self.entity_definitions[new_alias] = self.entity_definitions[alias]
                del(self.entity_definitions[alias])
            else:
                self.association_definitions[new_alias] = self.association_definitions[alias]
                del(self.association_definitions[alias])

        #add missing pks
        if gen_missing_pks:
            for entity in self.entity_definitions.values():
                entity.add_pk_if_missing(infer_columns = infer_pk_cols, columns = default_pk_cols, hash_by_default = hash_by_default)
            for association in self.association_definitions.values():
                association.add_pk_if_missing(
                    infer_columns = False,
                    columns = self.get_entity_definition_by_name(association.src_alias).get_columns_from_pk() | \
                              self.get_entity_definition_by_name(association.dst_alias).get_columns_from_pk(),
                    suffix = association.name
                )

        # add conditions
        if add_conditions:
            for entity in self.entity_definitions.values():
                entity.auto_generate_conditions()

        # add parsers
        if make_parsers:
            for entity in list(self.entity_definitions.values()) + list(self.association_definitions.values()):
                for property in entity.property_definitions.values():
                    property.add_datatype_parser_if_needed(timezone = timezone)

        self.refresh_schema()



        


def _add_missing_association_pks(flight, edmAPI, infer_columns = False, columns = [], hash_by_default = False):
    for entname, entity in flight["associationDefinitions"].items():
        if infer_columns:
            columns = list(clean.utils.get_cols_from_pk(flight["entityDefinitions"][entity["src"]], edmAPI) | clean.utils.get_cols_from_pk(flight["entityDefinitions"][entity["dst"]], edmAPI))
        keyprops = ["ol.id"]
        real_keyprops = clean.utils.get_primary_keys(entity['fqn'], edmAPI)
        if real_keyprops:
            keyprops = real_keyprops
        theseprops = list(entity['propertyDefinitions'].keys())
        overlap = set(keyprops) & set(theseprops)
        if len(overlap) == 0:
            if not hash_by_default:
                if len(columns) == 0:
                    entity['propertyDefinitions'][keyprops[0]] = {"type":keyprops[0]}
                    print(flight, "add column(s) for " + entname + ": " + keyprops[0])
                elif len(columns) == 1:
                    entity['propertyDefinitions'][keyprops[0]] = {"type":keyprops[0], "column":columns[0]}
                else:
                    entity['propertyDefinitions'][keyprops[0]] = {"type":keyprops[0], "transforms":[{"transforms.ConcatTransform":None, "columns":columns}]}
            else:
                entity['propertyDefinitions'][keyprops[0]] = {"type":keyprops[0], "transforms":[{"transforms.HashTransform":None, "columns":columns, "hashFunction":"sha256"}]}


def _write_trans_conds_list(trans_conds_list, trans_conds, depth):
    out_string = ""
    prefix_cond = trans_conds + '.'
    prefix_tran = "transforms."
    for tc in trans_conds_list:
        keys = list(tc.keys())
        if keys == ["column"]:
            out_string += " " * depth + "- !<transforms.ColumnTransform>\n" + \
            " " * (depth + 2) + 'column: "' + tc["column"] + '"\n'
        elif keys == ["value"]:
            out_string += " " * depth + "- !<transforms.ValueTransform>\n" + \
            " " * (depth + 2) + 'value: "' + tc["value"] + '"\n'
        else:
            tc_name = next((s for s in tc.keys() if prefix_cond in s or prefix_tran in s), None)
            if not tc_name:
                raise ValueError(str(tc.keys()))
            if prefix_cond in tc_name or prefix_tran in tc_name:
                out_string += " " * depth + "- !<" + tc_name + '>'
            else:
                out_string += " " * depth + "- !<" + prefix_cond + tc_name + '>'
            if tc[tc_name] is not None:
                out_string += ' ' + str(tc[tc_name])
            out_string += '\n'
            depth += 2
            for argkey, argval in sorted(tc.items()):
                if prefix_cond not in argkey and prefix_tran not in argkey:
                    out_string += " " * depth + argkey + ':'
                    if type(argval) == list:
                        if len(argval) == 0:
                            out_string += ' []\n'
                        elif type(argval[0]) == dict:
                            out_string += '\n' + _write_trans_conds_list(argval, trans_conds, depth)
                        else:
                            out_string += ' [' + clean.cols_to_string_with_dubquotes(argval) + ']\n'
                    elif type(argval) == str:
                        out_string += ' "' + str(argval) + '"\n'
                    else:
                        out_string += ' ' + str(argval) + '\n'
            depth -= 2
    return out_string



def deduce_edm_object(name, edm_api = None, category = "entity", from_pool = None):
    """
    Deduces which fqn is meant by the given string.

    Can be used (like in the fill_in function) to avoid needing to remember the namespaces of entity/property types.
    """

    name = re.sub("[0-9]+", "", name).replace(" ","")
    if "." in name:
        nn = name.split(".")
        return (nn[0], nn[1])
    if name == "is":
        return ("o", "is")
    if name in {"person", "datetime"}:
        return ("general", name)
    if from_pool is None:
        if category in ["entity", "association"]:
            from_pool = edm_api.get_all_entity_types()
        else:
            from_pool = edm_api.get_all_property_types()
    search_space = {x.type.namespace: x.type.name for x in from_pool if x.type.name.lower() == name.lower() and "-d" not in x.type.name.lower() and "-d" not in x.description.lower() and "-d" not in x.title.lower()}
    if len(search_space) == 0:
        return ("ol", name)
    if "ol" in search_space.keys():
        key = "ol"
    else:
        keylist = list(search_space.keys())
        key = keylist[0]
    return (key, search_space[key])


def _delete_column_from_object(tr_con_dict, column, context = []):
    """
    Delete a column from a transformation or condition while preserving syntax
    """

    if isinstance(tr_con_dict,list):
        index = 0
        while index < len(tr_con_dict):
            if _delete_column_from_object(tr_con_dict[index], column, context = context):
                tr_con_dict.pop(index)
            else:
                index += 1
        return not tr_con_dict
    elif isinstance(tr_con_dict, dict):
        keys_to_delete = []
        scan = next((s for s in tr_con_dict.keys() if "conditions." in s or "transforms." in s), None)
        new_context = context + ([scan] if scan else [])
        for k,v in tr_con_dict.items():
            if k == "transforms.ValueTransform":
                return "transforms.ConcatCombineTransform" in context
            if k.startswith('column'):
                if isinstance(v, list):
                    while column in v:
                        v.remove(column)
                    return not v
                return v == column
            if k != scan and _delete_column_from_object(v, column, context = new_context):
                keys_to_delete.append(k)
        for k in keys_to_delete:
            del tr_con_dict[k]
        remaining_keys = list(tr_con_dict.keys())
        return (not remaining_keys) or (len(remaining_keys) == 1 and remaining_keys[0] == scan)
    return True


def _remove_clutter(value):
    for symbol in [' ', "\'", "{", "}", "(", ")", "[", "]"]:
        value = value.replace(symbol, "")
    return value

def _parse_transforms(value):
    return _parse_functions(value, 'transformations')

def _parse_conditions(value):
    return _parse_functions(value, 'conditions')

def _parse_functions(value, kind):
    if kind == 'transformations':
        splitters = ['transforms.', 'com.openlattice.shuttle.transforms']
        hider = 'Transforms'
        keyword = 'transforms'
    elif kind == 'conditions':
        splitters = ['conditions.']
        hider = 'Conditions'
        keyword = "conditions"

    transforms = []
    columns = []
    for hlp in value:
        value = {}
        key = None
        for k,v in hlp.items():
            if re.findall("|".join(splitters), k):
                key = re.split("|".join(splitters), k)[::-1][0]
            elif k == keyword:
                parsed = _parse_functions(v, kind)
                columns += parsed['columns']
                transforms += parsed['transformations']            
            else:
                value[k] = v
                if k.startswith('column'):
                    if isinstance(v, str):
                        columns.append(v)
                    elif isinstance(v, list):
                        columns += v
                    else:
                        raise ValueError("Unknown type for columns in transformation %s"%key)
        if not key:
            raise ValueError("It is not clear what you mean by %s"%(str(value)))
        transforms.append({key: value})

    return {kind: transforms, "columns": list(set(columns))}

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

