from pyntegrationsncric.pyntegrations.ca_ncric.utils.integration_base_classes import Integration
import pandas as pd
import pytz


# Since BOSS3 data has similar structure to SCSO, created a one size fits all cleaning function
# with the ability to pass in datasource
# Because BOSS3 is not appended to any of the IDs, while "SCSO" is appended to all of the IDs,
# pass in None for BOSS3 to make joining strings easier
class ALPRIntegration(Integration):


    def clean_row(cls, row, datasource = None):
        newdict = pd.Series()

        newdict['red_vrm'] = row.red_vrm

        if datasource == None:
            newdict['datasource'] = "BOSS3"
        else: 
            # BOSS3 images are under a different table
            newdict['datasource'] = datasource
            newdict['red_patch'] = row.red_patch
            newdict['red_overview'] = row.red_overview

        newdict['date'] = pytz.timezone("America/Los_Angeles").localize(row.date)
        newdict['latlon'] = ",".join([str(row.Latitude), str(row.Longitude)])
        newdict['siteid'] = row.siteid
        newdict['sitedescr'] = row.sitedescr
        newdict['sourceid'] = row.sourceid
        newdict['standardized_agency_name'] = row.standardized_agency_name

        newdict['location_id'] = "-".join([str(row.Latitude), str(row.Longitude)])

        # having issues with just setting newdict['red_misread'] = row.red_misread even though
        # row.red_misread is a boolean variable. Clean and upload turns it into a string lower case 'false'
        # Not clear why -- but double checked that at least this produces the correct results
        if (row.red_misread == "true" or row.red_misread): 
            newdict['red_misread'] = True 
        else: newdict['red_misread'] = False
        
        if (row.red_manualentry == "true" or row.red_manualentry): 
            newdict['red_manualentry'] = True  
        else: newdict['red_manualentry'] = False

        # BOSS3 is not appended to the IDs, so to get around that, passed a None type to the datasource variable in integration definition
        # filtering None type in the actual joins
        newdict['agencies_id'] = "_".join(filter(None, [str(row.siteid), datasource]))
        newdict['vehicle_records_id'] = "_".join(filter(None, [str(row.red_id), datasource]))
        newdict['imagesources_id'] = "_".join(filter(None, [str(row.sourceid), datasource]))
        newdict['has_id'] = "_".join(filter(None, [row.red_vrm, str(row.red_id), datasource]))
        newdict['recordedby1_id'] = "_".join(filter(None, [str(row.red_id), str(row.sourceid), datasource]))
        newdict['recordedby2_id'] = "_".join(filter(None, [str(row.red_id), str(row.siteid), datasource]))
        newdict['recordedby3_id'] = "_".join(filter(None, [str(row.red_id), str(row.standardized_agency_name), datasource]))
        newdict['includes1_id'] = "_".join(filter(None, [str(row.red_id), str(newdict.date), datasource]))
        newdict['includes2_id'] = "_".join(filter(None, [str(row.sourceid), str(newdict.date), datasource]))
        newdict['collectedby_id'] = "_".join(filter(None, [str(row.sourceid), str(row.siteid), datasource]))
        newdict['collectedby2_id'] = "_".join(filter(None, [str(row.sourceid), str(row.standardized_agency_name), datasource]))

        return newdict


class ALPRHitsIntegration(Integration):

    def clean_row(cls, row, datasource = None):
        newdict = pd.Series()

        newdict['hts_VRM'] = row.hts_VRM
        newdict['vehicle_records_id'] = "_".join(filter(None, [str(row.hts_red_ID), datasource]))
        newdict['hts_Hotlist'] = row.hts_Hotlist

        # Note: for BOSS3, datasource is not appended to the end; to keep the code simpler, 
        # passed in None for BOSS3 as datasource so that joining strings is easier
        if datasource is None:
            newdict['datasource'] = "BOSS3"
        else:
           newdict['datasource'] = datasource

        newdict['hts_Timestamp'] = pytz.timezone("America/Los_Angeles").localize(row.hts_Timestamp)
        newdict['notifications_id'] = "_".join(filter(None, [row.hts_VRM, datasource]))

        newdict['has_id'] = "_".join(filter(None, [row.hts_VRM, str(row.hts_red_ID), datasource]))
        newdict['resultsin1_id'] = "_".join(filter(None, [str(row.hts_red_ID), datasource]))

        return newdict


# class ALPRVehiclesIntegration(Integration):
#
#     def clean_row(cls, row, datasource = None):
#         newdict = pd.Series()
#         newdict['red_vrm'] = row.red_vrm
#
#         if datasource == None:
#             newdict['datasource'] = "BOSS3"
#         else: newdict['datasource'] = datasource
#
#         return newdict

class ALPRImageSourceIntegration(Integration):

    def clean_row(cls, row, datasource = None):
        newdict = pd.Series()

        newdict['imagesources_id'] = "_".join(filter(None, [str(row.sourceid), datasource]))
        newdict['sourcename'] = row.sourcename
        newdict['srcdescr'] = row.srcdescr

        if (row.fixedmobile == "true" or row.fixedmobile): 
            newdict['fixedmobile'] = True 
        else:  newdict['fixedmobile'] = False

        if datasource == None:
            newdict['datasource'] = "BOSS3"
        else: newdict['datasource'] = datasource

        return newdict

class ALPRAgenciesIntegration(Integration):
    
    def clean_row(cls, row, datasource = None):
        newdict = pd.Series()

        newdict['agencies_id'] = "_".join(filter(None, [str(row.siteid), datasource]))
        newdict['sitedescr'] = row.sitedescr
        if datasource == None:
            newdict['datasource'] = "BOSS3"
        else: newdict['datasource'] = datasource

        return newdict


