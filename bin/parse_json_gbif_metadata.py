#!/usr/bin/env python3

import argparse
import os
import json
import sys
import string
import numbers

# Define which fields to fetch from GBIF JSON
fetch = [
    ("GBIF_ID", ("gbifID",)),
    ("DATASET_KEY", ("datasetKey",)),
    ("OCCURRENCE_ID", ("occurrenceID",)),
    ("KINGDOM", ("kingdom",)),
    ("PHYLUM", ("phylum",)),
    ("CLASS", ("class",)),
    ("ORDER", ("order",)),
    ("FAMILY", ("family",)),
    ("GENUS", ("genus",)),
    ("SPECIES", ("species",)),
    ("TAXON_RANK", ("taxonRank",)),
    ("SCIENTIFIC_NAME", ("scientificName",)),
    ("VERBATIM_SCIENTIFIC_NAME", ("verbatimScientificName",)),
    ("COUNTRY_CODE", ("countryCode",)),
    ("LOCALITY", ("locality",)),
    ("STATE_PROVINCE", ("stateProvince",)),
    ("OCCURRENCE_STATUS", ("occurrenceStatus",)),
    ("INDIVIDUAL_COUNT", ("individualCount",)),
    ("PUBLISHING_ORG_KEY", ("publishingOrgKey",)),
    ("DECIMAL_LATITUDE", ("decimalLatitude",)),
    ("DECIMAL_LONGITUDE", ("decimalLongitude",)),
    ("COORDINATE_UNCERTAINTY", ("coordinateUncertaintyInMeters",)),
    ("HABITAT", ("habitat",)),
    ("ELEVATION", ("elevation",)),
    ("DEPTH", ("depth",)),  
    ("EVENT_DATE", ("eventDate",)),
    ("BASIS_OF_RECORD", ("basisOfRecord",)),  
    ("INSTITUTION_CODE", ("institutionCode",)),   
    ("COLLECTION_CODE", ("collectionCode",)),
    ("CATALOG_NUMBER", ("catalogNumber",)),
    ("RECORD_NUMBER", ("recordNumber",)),
    ("IDENTIFIED_BY", ("identifiedBy",)),
    ("DATE_IDENTIFIED", ("dateIdentified")),
    ("RECORDED_BY", ("recordedBy",)),
    ("LICENSE", ("licence")),
]

def parse_args(args=None):
    Description = "Parse GBIF occurrence JSON data from a file and extract metadata."
    Epilog = "Example usage: python fetch_gbif_metadata.py <FILE_IN> <FILE_OUT> --limit 10"

    parser = argparse.ArgumentParser(description=Description, epilog=Epilog)
    parser.add_argument("FILE_IN", help="Input JSON file containing GBIF occurrence data.")
    parser.add_argument("FILE_OUT", help="Output file for saving the fetched metadata.")
    parser.add_argument("--limit", type=int, default=10, help="Number of records to process from the input JSON.")
    parser.add_argument("--version", action="version", version="%(prog)s 1.0")
    return parser.parse_args(args)

def make_dir(path):
    if len(path) > 0:
        os.makedirs(path, exist_ok=True)

def print_error(error, context="Line", context_str=""):
    error_str = "ERROR: {}".format(error)
    if context != "":
        if context_str != "":
            error_str = "ERROR: {}\n{}: '{}'".format(
                error, context.strip(), context_str.strip()
            )
        else:
            error_str = "ERROR: {}\n{}".format(error, context.strip())

    print(error_str)
    sys.exit(1)

def read_json_file(file_in):
    try:
        with open(file_in, "r") as f:
            data = json.load(f)
        return data.get('results', [])
    except Exception as e:
        print_error(f"Failed to read JSON file. Error: {e}")

def parse_json(records, file_out):
    param_list = []

    for record in records:
        for f in fetch:
            param = find_element(record, f[1], index=0)
            if param is not None:
                if isinstance(param, numbers.Number):
                    param = str(param)

                if any(p in string.punctuation for p in param):
                    param = '"' + param + '"'

                param_list.append([f[0], param])

    if len(param_list) > 0:
        out_dir = os.path.dirname(file_out)
        make_dir(out_dir)
        with open(file_out, "w") as fout:
            fout.write(",".join(["#paramName", "paramValue"]) + "\n")
            for param_pair in param_list:
                fout.write(",".join(param_pair) + "\n")
    else:
        print_error("No parameters found!")

def find_element(data, fields, index=0):
    if index < len(fields):
        key = fields[index]
        if key in data:
            sub_data = data[key]
            if type(sub_data) in [list, dict]:
                return find_element(sub_data, fields, index + 1)
            return sub_data
        else:
            return None
    return None

def main(args=None):
    args = parse_args(args)
    records = read_json_file(args.FILE_IN)
    parse_json(records, args.FILE_OUT)

if __name__ == "__main__":
    sys.exit(main())

