#!/usr/bin/env python3

import argparse
import os
import json
import sys
import string
import numbers
import requests

# Define which fields to fetch from the GBIF JSON response
fetch = [
    ("GBIF_ID", ("gbifID",)),
    ("SCIENTIFIC_NAME", ("scientificName",)),
    ("KINGDOM", ("kingdom",)),
    ("PHYLUM", ("phylum",)),
    ("CLASS", ("class",)),
    ("ORDER", ("order",)),
    ("FAMILY", ("family",)),
    ("GENUS", ("genus",)),
    ("SPECIES", ("species",)),
    ("DECIMAL_LATITUDE", ("decimalLatitude",)),
    ("DECIMAL_LONGITUDE", ("decimalLongitude",)),
    ("COUNTRY_CODE", ("countryCode",)),
    ("EVENT_DATE", ("eventDate",)),
    ("BASIS_OF_RECORD", ("basisOfRecord",)),
    ("DATASET_KEY", ("datasetKey",)),
    ("INSTITUTION_CODE", ("institutionCode",)),
    ("COLLECTION_CODE", ("collectionCode",)),
    ("CATALOG_NUMBER", ("catalogNumber",)),
    ("RECORDED_BY", ("recordedBy",)),
    ("OCCURRENCE_STATUS", ("occurrenceStatus",)),
    ("TAXON_RANK", ("taxonRank",)),
    ("COORDINATE_UNCERTAINTY", ("coordinateUncertaintyInMeters",)),
    ("HABITAT", ("habitat",)),
    ("LOCALITY", ("locality",)),
    ("VERBATIM_LOCALITY", ("verbatimLocality",)),
    ("ELEVATION", ("elevation",)),
    ("DEPTH", ("depth",)),
]

def parse_args(args=None):
    Description = "Fetch and parse GBIF occurrence data to extract metadata."
    Epilog = "Example usage: python fetch_gbif_metadata.py <FILE_OUT> --species <SCIENTIFIC_NAME>"

    parser = argparse.ArgumentParser(description=Description, epilog=Epilog)
    parser.add_argument("FILE_OUT", help="Output file for saving the fetched metadata.")
    parser.add_argument("--species", help="Scientific name of the species (Genus species) to search in GBIF.", required=True)
    parser.add_argument("--limit", type=int, default=10, help="Number of records to fetch from GBIF.")
    parser.add_argument("--version", action="version", version="%(prog)s 1.0")
    return parser.parse_args(args)

def make_dir(path):
    """Create a directory if it doesn't exist."""
    if len(path) > 0:
        os.makedirs(path, exist_ok=True)

def print_error(error, context="Line", context_str=""):
    """Helper function to print an error message and exit."""
    error_str = f"ERROR: {error}"
    if context:
        error_str += f"\n{context}: '{context_str}'" if context_str else f"\n{context}"
    print(error_str)
    sys.exit(1)

def fetch_gbif_data(species_name, limit):
    """Fetch occurrence data from GBIF API based on the scientific name."""
    gbif_api_url = f"https://api.gbif.org/v1/occurrence/search?scientificName={species_name}&limit={limit}"
    response = requests.get(gbif_api_url)

    if response.status_code == 200:
        data = response.json()
        return data.get('results', [])
    else:
        print_error(f"Failed to fetch data from GBIF API. Status code: {response.status_code}")

def parse_json(records, file_out):
    """Parse the JSON records from GBIF and save them to a CSV file."""
    param_list = []

    for record in records:
        for f in fetch:
            param = find_element(record, f[1], index=0)
            if param is not None:
                if isinstance(param, numbers.Number):
                    param = str(param)
                # Add quotes if the value contains punctuation
                if any(p in string.punctuation for p in param):
                    param = f'"{param}"'
                param_list.append([f[0], param])

    if param_list:
        out_dir = os.path.dirname(file_out)
        make_dir(out_dir)
        with open(file_out, "w") as fout:
            fout.write(",".join(["#paramName", "paramValue"]) + "\n")
            for param_pair in param_list:
                fout.write(",".join(param_pair) + "\n")
    else:
        print_error("No parameters found!")

def find_element(data, fields, index=0):
    """Recursively search through the JSON data for the specified fields."""
    if index < len(fields):
        key = fields[index]
        if key in data:
            sub_data = data[key]
            if isinstance(sub_data, (list, dict)):
                return find_element(sub_data, fields, index + 1)
            return sub_data
    return None

def main(args=None):
    args = parse_args(args)
    records = fetch_gbif_data(args.species, args.limit)
    parse_json(records, args.FILE_OUT)

if __name__ == "__main__":
    sys.exit(main())

