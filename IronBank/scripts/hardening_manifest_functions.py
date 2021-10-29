#!/usr/local/bin/python3
import os
import sys
import shutil
import requests
import yaml
import subprocess
import hashlib

def check_for_existing_manifest():
    """ Check for existing manifest and ask user whether they intended the existing
        hardening_manifest to be appended with their new changes. """
    manifest_exist = os.path.isfile("hardening_manifest/hardening_manifest.yaml")
    append_to_manifest = False
    if manifest_exist:
        question = ('\nWARNING: A manifest already exists.\nIf you would like to '
                    'update it with new packages you have added please type '
                    '"y"\nIf you would like to create a new manifest, please type "n" and '
                    'move the current one located at hardening_manifest/hardening_manifest.yaml, '
                    'to a new location.\n')
        reply = str(input(question+' (y/n): ')).lower()
        if reply == 'y':
            append_to_manifest = True
        elif reply == 'n':
            sys.exit("Please move existing manifest.")
        else:
            sys.exit('Please enter "y" or "n"')
    return append_to_manifest

def multi_envs_check(pkg_managers_to_run: list):
    """Check to make sure some tool requirements are met"""
    print("\nChecking environment...\n")
    for package_manager in pkg_managers_to_run:
        if package_manager == "npm":
            # Checking for npm
            if not shutil.which('npm'):
                sys.exit('ERROR: It seems npm is not installed '
                         'or is not in path, please fix to continue.\n')

        if package_manager == "pip":
            # Checking for pip
            try:
                grepOut = subprocess.check_output("python3 -m pip", shell=True)
            except subprocess.CalledProcessError as grepexc:
                sys.exit('ERROR: It seems pip3 is not installed '
                        'or is not in path, "python3 -m pip ..." needs to run. Please fix to continue.\n')
            # Check connection to https://pypi.org/
            try:
                req = requests.head("https://pypi.org/")
            except requests.exceptions.Timeout:
                print("ERROR: Unable to connect to pypi.org\n")
            except requests.exceptions.TooManyRedirects:
                print("ERROR: Unable to connect to pypi.org\n")
            except requests.exceptions.RequestException as exception:
                print("ERROR: Unable to connect to pypi.org\n")
                raise SystemExit(exception)

        if package_manager == "gem":
            # Check for gem
            if not shutil.which('gem'):
                sys.exit('ERROR: It seems gem is not installed '
                         'or is not in path, please fix to continue.\n')


def create_template():
    """ Create the beginning of the hardening manifest by writing necessary fields.
    The yaml.safe_load module creates a python dictionary that is formatted
    correctly for yaml.dumps() to write the below yaml in this same format. """
    start_of_manifest = yaml.safe_load('''
    apiVersion: v1
    name: ""
    tags:
    - ""
    args:
      BASE_IMAGE: ""
      BASE_TAG: ""
    labels:
      org.opencontainers.image.title: ""
      org.opencontainers.image.description: ""
      org.opencontainers.image.licenses: ""
      org.opencontainers.image.url: ""
      org.opencontainers.image.vendor: ""
      org.opencontainers.image.version: ""
      mil.dso.ironbank.image.keywords: ""
      mil.dso.ironbank.image.type: ""
    maintainers:
    - email: ""
      name: ""
      username: ""
      cht_member: false
    ''')
    return start_of_manifest

def get_rest_of_manifest_values():
    """ If an existing manifest is present then we do not want to overwrite any fields
    the user may have filled out. So we want to read in everything but the resources:
    section and use that when generating the file. """
    stream = open('hardening_manifest/hardening_manifest.yaml', 'r')
    existing_manifest = yaml.safe_load(stream)
    del existing_manifest['resources']
    return existing_manifest

def generate_hardening_manifest(resources_dict_yaml_format: dict):
    """Take both yaml formatted dictionaries and combine them into the final hardening manifest."""
    manifest_exist = os.path.isfile("hardening_manifest/hardening_manifest.yaml")
    if manifest_exist:
        try:
            start_of_manifest = get_rest_of_manifest_values()
        except:
            start_of_manifest = create_template()
    else:
        start_of_manifest = create_template()
    stream = open('hardening_manifest/hardening_manifest.yaml', 'w')
    yaml.dump(start_of_manifest, stream, explicit_start=True)
    yaml.dump(resources_dict_yaml_format, stream, explicit_start=False, indent=2)

def generate_resources_section(formatted_package_data: list, append_to_manifest: bool):
    """ Use the dictionaries from format_pkg_data to format the resources section of hardening
    manifest. The dictionary returned here is in a specific format so that yaml.dump() properly
    formats the yaml it is writing. If append_to_manifest is true then load existing manifest
    and add to it rather than create a new resource section. """
    if append_to_manifest:
        try:
            stream = open('hardening_manifest/hardening_manifest.yaml', 'r')
            existing_manifest = yaml.safe_load(stream)
            existing_resources_section = existing_manifest['resources']
            for pkg_dict in formatted_package_data:
                package_manifest_entry = {
                    'url': pkg_dict['pkg_url'],
                    'filename': pkg_dict['pkg_filename'],
                    'validation':
                    {
                        'type': pkg_dict['sha_type'],
                        'value': pkg_dict['pkg_sha']
                    }
                }
                existing_resources_section.append(package_manifest_entry)
            resources_dict_yaml_format = {'resources': existing_resources_section}
            return resources_dict_yaml_format
        except:
            resources_dict_yaml_format = {'resources':[]}
            for pkg_dict in formatted_package_data:
                package_manifest_entry = {
                    'url': pkg_dict['pkg_url'],
                    'filename': pkg_dict['pkg_filename'],
                    'validation':
                    {
                        'type': pkg_dict['sha_type'],
                        'value': pkg_dict['pkg_sha']
                    }
                }
                resources_dict_yaml_format['resources'].append(package_manifest_entry)
            return resources_dict_yaml_format
    else:
        resources_dict_yaml_format = {'resources':[]}
        for pkg_dict in formatted_package_data:
            package_manifest_entry = {
                'url': pkg_dict['pkg_url'],
                'filename': pkg_dict['pkg_filename'],
                'validation':
                {
                    'type': pkg_dict['sha_type'],
                    'value': pkg_dict['pkg_sha']
                }
            }
            resources_dict_yaml_format['resources'].append(package_manifest_entry)
        return resources_dict_yaml_format

def compare_existing_manifest_to_requirements(master_req_and_dep_list: list):
    """ Read in existing manifest and compare those values to whats in the master_req_and_dep_list
    so we only get information about packages that are not yet in the existing manifest. """
    stream = open('hardening_manifest/hardening_manifest.yaml', 'r')
    existing_manifest = yaml.safe_load(stream)
    existing_manifest_resources_section = existing_manifest['resources']
    existing_packages_list = []
    for entry in existing_manifest_resources_section:
        filename = entry['filename']
        existing_packages_list.append(filename)
    # Compare master list passed into function and the existing
    # list to deduplicate entries into a new list.
    new_packages = []
    for filename in master_req_and_dep_list:
        if filename not in existing_packages_list:
            new_packages.append(filename)
    return new_packages

def sha_compare_existing_manifest_to_requirements(master_list_of_pkg_dicts: list):
    """ Read in existing manifest and compare those values to whats in the new manifest resources section
    so we only get information about packages that are not yet in the existing manifest. """
    try:
        stream = open('hardening_manifest/hardening_manifest.yaml', 'r')
        existing_manifest = yaml.safe_load(stream)
        existing_manifest_resources_section = existing_manifest['resources']
        existing_packages_list = []
        for entry in existing_manifest_resources_section:
            sha = entry['validation']['value']
            existing_packages_list.append(sha)
        # Compare master list passed into function and the existing
        # list to deduplicate entries into a new list.
        new_packages = []
        for entry in master_list_of_pkg_dicts:
            if entry['pkg_sha'] not in existing_packages_list:
                new_packages.append(entry)
        return new_packages
    except:
        return master_list_of_pkg_dicts


def sha256_Checksum(url):
    m = hashlib.sha256()
    r = requests.get(url)
    for data in r.iter_content(8192):
            m.update(data)
    return m.hexdigest()
