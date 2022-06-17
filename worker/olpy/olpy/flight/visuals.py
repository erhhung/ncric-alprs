from collections import Counter
import matplotlib.pyplot as plt
from pprint import pprint
import openlattice
import pandas as pd
import numpy as np
import palettable
import graphviz
import random
import yaml
import uuid
import copy
import os
import re

cols = palettable.tableau.ColorBlind_10.hex_colors
cols += palettable.tableau.PurpleGray_12.hex_colors
cols += palettable.tableau.Tableau_20.hex_colors
cols += palettable.tableau.GreenOrange_12.hex_colors
cols += palettable.tableau.BlueRed_12.hex_colors

class EdmViz(object):
    def __init__(self, flight=None, schema=None, flights = None, engine = 'dot', splines = 'curved', aesthetics = {}):
        self.graph = graphviz.Digraph(comment='Flight',engine=engine, graph_attr={"splines": splines})
        if sum([flight != None, schema != None, flights != None]) != 1:
            raise ValueError("Please specify either a flight, multiple flights or a schema.")
        elif schema != None:
            self.schema = schema
        elif flight != None:
            self.edm_api = flight.edm_api
            self.flight = flight
            self.schema = flight.schema
        elif flights != None:
            self.edm_api = flights[0].edm_api
            self.flights = flights
        self.aesthetics = self.get_aesthetics(manual_aesthetics = aesthetics)

    def get_aesthetics(self, manual_aesthetics):
        with open (
            os.path.join(
                os.path.dirname(
                    os.path.realpath(__file__)
                    ),
                'resources/aesthetics.yaml'
                ), 'r') as infile:
            aesth = yaml.load(infile, Loader=yaml.FullLoader)

        outdict = {}
        for key in ['entityDefinitions', 'associationDefinitions']:
            default = {**aesth['all'], **aesth[key]}
            withmanual = {**default, **{k:v for k,v in manual_aesthetics.items() if not k in ['entityDefinitions', 'associationDefinitions']}}
            if key in manual_aesthetics:
                withmanual = {**default, **manual_aesthetics[key]}
            outdict[key] = withmanual
        if 'important' in manual_aesthetics:
            outdict['important'] = manual_aesthetics['important']
        return outdict

    def add_entities(self, schema, fields = [], important = []):
        # aesthetics
        aesthetics = copy.deepcopy(self.aesthetics['entityDefinitions'])
        important_aesthetics = copy.deepcopy(self.aesthetics['entityDefinitions'])
        if 'important' in self.aesthetics.keys():
            important_aesthetics.update(self.aesthetics['important'])
        
        # grab nodes
        for title, object in schema['nodes'].items():
            fqn = set([x['fqn'] for x in object['objects']])
            assert len(fqn) == 1
            fqn = list(fqn)[0]
            aes = important_aesthetics if fqn in important or title in important else aesthetics
            self.graph.attr('node', aes)
            if not fqn == title:
                thistitle = "{title} ({fqn})".format(title=title, fqn = fqn)
            else:
                thistitle = title
            box = create_box(title=thistitle, object=object, fields=fields, edmApi = self.edm_api, **aes)
            self.graph.node(title, box)


    def add_associations(self, schema, fields = [], split_associations = False,plotlinks=True, important = []):

        aesthetics = copy.deepcopy(self.aesthetics['associationDefinitions'])
        important_aesthetics = copy.deepcopy(self.aesthetics['associationDefinitions'])
        if 'important' in self.aesthetics.keys():
            important_aesthetics.update(self.aesthetics['important'])
        edge_nodes_done = []
        edge_edges_done = []

        for title, object in schema['edges'].items():

            # set color if rainbox
            if self.aesthetics['associationDefinitions']['color'] == 'rainbow':
                col = random.choice(cols)
                aesthetics['color'] = col

            fqn = set([x['fqn'] for x in object['objects']])
            assert len(fqn) == 1
            fqn = list(fqn)[0]
            if len(fqn.split(".")) < 2:
                print("this is it: " + str(title) + str(object) + str(fqn) + str(schema))
            association_type_id = self.edm_api.get_entity_type_id(namespace = fqn.split('.')[0], name = fqn.split('.')[1])
            association_type = self.edm_api.get_association_type(association_type_id)
            direction = "both" if association_type.bidirectional else "forward"

            # create node if splitassocaitions
            if split_associations:
                if not fqn == title:
                    thistitle = "{title} ({fqn})".format(title=title, fqn = fqn)
                else:
                    thistitle = title
                box = create_box(title=thistitle, object=object, fields=fields, edmApi = self.edm_api, **aesthetics)
                self.graph.node(title, box)

            if plotlinks:
                halfdone = {"srcs": [], "dsts": []}
                for edge in object['edges']:
                    aes = important_aesthetics if edge[0] in important or edge[1] in important else aesthetics
                    self.graph.attr('node', aes)
                    
                    if not split_associations:
                        self.graph.edge(edge[0], edge[1],
                                   label=title,  dir=direction, **aes)
                    else:
                        if not edge[0] in halfdone['srcs']:
                            self.graph.edge(edge[0], title, label=title, dir = direction, **aes)
                            halfdone['srcs'].append(edge[0])
                        if not edge[1] in halfdone['dsts']:
                            self.graph.edge(title, edge[1], label = edge[1], dir=direction, **aes)
                            halfdone['dsts'].append(edge[1])
        
    
    def get_schema(self, type = "fqn"):
        if 'flight' in dir(self):
            schema = self.flight.transform_schema(type)
        elif 'flights' in dir(self):
            schema = {"nodes": {}, "edges": {}}
            for fl in self.flights:
                newschema = fl.transform_schema(type)

                schema = combine_schemas(schema, newschema)
        else:
            raise ValueError("No flight or flights were specified")
        return schema

    def create_flight_plot(self, type="fqn", fields = [], split_associations=False, plotlinks=True, important = []):
        schema = self.get_schema(type)
        self.add_entities(schema = schema, fields = fields, important = important)
        self.add_associations(schema = schema, fields = fields, split_associations=split_associations, plotlinks=plotlinks, important = important)
        return self.graph


def combine_schemas(schema1, schema2):
    fullschema = copy.deepcopy(schema1)

    # nodes
    for key, objects in schema2['nodes'].items():
        if not key in list(schema1['nodes'].keys()):
            fullschema['nodes'][key] = objects
        else:
            fullschema['nodes'][key]['objects'] += objects['objects']

    # edges
    for key, objects in schema2['edges'].items():
        if not key in list(schema1['edges'].keys()):
            fullschema['edges'][key] = objects
        else:
            for obj, edge in zip(objects['objects'], objects['edges']):
                if edge in fullschema['edges'][key]['edges']:
                    continue
                else:
                    fullschema['edges'][key]['objects'].append(obj)
                    fullschema['edges'][key]['edges'].append(edge)
    return fullschema


def get_property_dict(entity, edmApi):
    fqn_split = entity['fqn'].split(".")
    try:
        entid = edmApi.get_entity_type_id(namespace=fqn_split[0], name=fqn_split[1])
        entedm = edmApi.get_entity_type(entid)
        primaries = [get_fqn(edmApi.get_property_type(x).type) for x in entedm.key]
    except openlattice.rest.ApiException as exc:
        print("Couldn't find entitytype %s, not distinguishing primary from secondary keys !"%entity['fqn'])
        primaries = []

    # create a dictionary with keys
    properties = {"primary": {}, "secondary": {}}
    for prop in entity['properties']:
        cols = get_columns(prop)
        if prop['fqn'] in primaries:
            properties['primary'][prop['fqn']] = cols
        else:
            properties['secondary'][prop['fqn']] = cols
    return properties

def print_string(instring, bold=False, fontcolor = 'white'):
    cutoff = 50
    if len(instring) > cutoff:
        instringsplit = instring.split(",")
        rows = []
        newstring = ""
        for ind, inpart in enumerate(instringsplit):
            suffix = "" if ind == len(instringsplit)-1 else ", "
            newstring += "%s%s"%(inpart, suffix)
            if len(newstring) > cutoff:
                rows.append(newstring)
                newstring = ""
        if len(newstring) > 0:
            rows.append(newstring)

    else:
        rows = [instring]

    outstring = ""
    for row in rows:
        if len(row) == 0:
            continue
        outstring += '''
        <tr>
            <td>
                <font color=\"{fontcolor}\">
                    {boldin}
                        {row}
                    {boldout}
                </font>
            </td>
        </tr>
        '''.format(
            row = row,
            boldin = "<b>" if bold else "",
            boldout = "</b>" if bold else "",
            fontcolor = fontcolor).replace("  ","")
    return outstring


def get_property_rows(entity, edmApi, **kwargs):
    props = get_property_dict(entity, edmApi)
    # create string
    outstring = ""
    for prim_fqn, columns in props['primary'].items():
        fullstring = "{fqn} ({cols})".format(fqn=prim_fqn, cols = ", ".join(columns))
        outstring += print_string(fullstring, bold = False, fontcolor = kwargs['fontcolor'])
    for fqn, columns in props['secondary'].items():
        fullstring = "{fqn} ({cols})".format(fqn=fqn, cols = ", ".join(columns))
        outstring += print_string(fullstring, bold = False, fontcolor = kwargs['propertyfontcolor'])
    return outstring

def get_primary_key_rows(entity, edmApi, **kwargs):

    fqn_split = entity['fqn'].split(".")
    try:
        entid = edmApi.get_entity_type_id(namespace=fqn_split[0], name=fqn_split[1])
        entedm = edmApi.get_entity_type(entid)
        primaries = [get_fqn(edmApi.get_property_type(x).type) for x in entedm.key]
    except openlattice.rest.ApiException as exc:
        primaries = []
        print("WARNING: could not find primary keys for %s"%entity['name'])
    
    # create a dictionary with primary keys
    prims = {}
    for prop in entity['properties']:
        if prop['fqn'] in primaries:
            if isinstance(prop['column'], str):
                cols = [prop['column']]
            else:
                cols = []
            if 'transforms' in prop.keys():
                cols += prop['transforms']['columns']
            prims[prop['fqn']] = cols

    # create string
    outstring = ""
    for prim_fqn, columns in prims.items():
        fullstring = "{fqn} ({cols})".format(fqn=prim_fqn, cols = ", ".join(columns))
        outstring += print_string(fullstring, bold = False, fontcolor = kwargs['fontcolor'])
    return outstring

def get_name(entity, edmApi, **kwargs):
    return print_string(entity['name'], bold = False, fontcolor = kwargs['fontcolor'])

def get_entityset_name(entity, edmApi, **kwargs):
    return print_string(entity['entityset_name'], bold = False, fontcolor = kwargs['fontcolor'])

def get_flight_name(entity, edmApi, **kwargs):
    return print_string(entity['flight_name'], bold = True, fontcolor = kwargs['fontcolor'])

def create_box(title, object, fields = [], edmApi=None, important=False, **kwargs):
    functions = {
        "primary_key": get_primary_key_rows,
        "properties": get_property_rows,
        "name": get_name,
        "entityset_name": get_entityset_name,
        "flight_name": get_flight_name
    }
    outtable = ""
    for entity in object['objects']:
        for field in fields:
            outtable += functions[field](entity, edmApi, **kwargs)

    box = '<<table border="{tableborder}" bgcolor="{bgcolor}" bordercolor="{bordercolor}" cellborder="{cellborder}" cellspacing="{cellspacing}" cellpadding="{cellpadding}">\
    <tr><td>\
    <font color=\"{titlefontcolor}\"><u><b>{fqn}</b></u></font>\
    </td></tr>\
    {string}\
    </table>>'.format(
         fqn = title,
         string = outtable,
         cellspacing = kwargs['cellspacing'],
         tableborder = kwargs['tableborder'],
         cellborder = kwargs['cellborder'],
         cellpadding = kwargs['cellpadding'],
         titlefontcolor = kwargs['titlefontcolor'],
         bgcolor = kwargs['tablebgcolor'],
         bordercolor = kwargs['tablebordercolor']
    )
    return box

def get_fqn(type):
    return ".".join([type.namespace, type.name])

def get_columns(property):
    if isinstance(property['column'], str):
        cols = [property['column']]
    else:
        cols = []
        if 'transforms' in property.keys():
            cols += property['transforms']['columns']
    return cols
