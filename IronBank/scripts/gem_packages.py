#!/usr/local/bin/python3
import shutil
import os
import sys
import re
import subprocess
import multiprocessing
from .pip_packages import get_requirements
from .hardening_manifest_functions import *


def gem_environment_check():
    """Check to make sure environment requirements are met"""
    print('\nChecking environment...\n')
    # Checking for gem
    if not shutil.which('gem'):
        sys.exit('ERROR: It seems gem is not installed '
                 'or is not in path, please fix to continue.\n')

    # Make sure gem-packages.txt has content
    file_size = os.stat("requirements_files/gem-packages.txt")
    if file_size.st_size == 0:
        sys.exit('ERROR: gem-packages.txt does not have any content.'
                 ' Please add required packages there.\n')


def get_gem_deps(package_string: str):
    """ Use the user provided requirement to get all dependencies """
    # Possible values for package_string: 
    # package_name OR package_name <boolOperator><version> 
    #   possible bool operators <, >, <=, >=, and =
    pkg_dep_list = []
    failed_list = []
    try:
        # If there is a bool operator in the string we need to capture that
        # and use it in the command for versioning
        char_list = [">", "<", "="]
        has_version_spec = [characters in char_list for characters in package_string]
        if True in has_version_spec:
            pkg_name, pkg_version_spec = package_string.split(" ")
            dependency_command_specific_version = "gem install {} -rq -v '{}' --explain 2> /dev/null".format(pkg_name, pkg_version_spec)
            output = subprocess.check_output(dependency_command_specific_version, shell=True)
            for word in output.decode('utf-8').split('\n')[1:]:
                pkg = word.strip()
                pkg_dep_list.append(pkg)
            return(pkg_dep_list, failed_list)
        else:
            # If just package_name then use this command
            dependency_command_latest_version =  "gem install {} -rq --explain 2> /dev/null".format(package_string)
            output = subprocess.check_output(dependency_command_latest_version, shell=True)
            for word in output.decode('utf-8').split('\n')[1:]:
                pkg = word.strip()
                pkg_dep_list.append(pkg)
            return(pkg_dep_list, failed_list)
    except:
        # If both failed add this package to the failed list
        failed_list.append(package_string)
        return(pkg_dep_list, failed_list)


def create_dep_list(requirements: list):
    """ Create master and failed list of packages """
    print("Retrieving metadata about gems...\n")
    master_list = []
    master_failed_list = []
    with multiprocessing.Pool(processes=15) as pool:
        vals = pool.imap(get_gem_deps, requirements)
        # Dedup and add packages to master or failed list
        for pkgs_list in vals:
            packages_list, failed_list = pkgs_list
            for pkg in packages_list:
                if pkg not in master_list:
                    master_list.append(pkg)
            for pkg in failed_list:
                if pkg not in master_failed_list:
                    master_failed_list.append(pkg)
    # Remove any null entries that may have been 
    # included when parsing and decoding in previous steps
    try:
        master_list.remove('')
    except:
        pass
    return(master_list, master_failed_list)


def get_sha(url: str):
    """ The package's hash lives on their site so we need to curl for it """
    # Example response (value of output var below)
    # b'    <h3 class="t-list__heading">SHA 256 checksum:</h3>\n    <div class="gem__sha">\n      6636e0262fec9b2b1b40775c5702944a36ad5649408e5a2e25f844760d4950f2\n'
    get_sha_command = "curl -s {} 2> /dev/null | grep -i 'gem__sha' -A1 -B1".format(url)
    output = subprocess.check_output(get_sha_command, shell=True)
    decoded_list = output.decode('utf-8').split('\n')
    sha_type_string = decoded_list[0]
    sha_value_string = decoded_list[2]
    
    # Parse HTML response for the sha type
    sha_type_string_2 = sha_type_string.split(">")[1]
    sha_type_uppercase = sha_type_string_2.split(" checksum")[0]
    sha_type = sha_type_uppercase.lower()

    # Strip spaces from string
    pkg_sha = sha_value_string.strip()
    return(pkg_sha, sha_type)


def split_name(package: str):
    """ Use regex to properly split the string into name and version spec """
    version_tuple = re.search('(-\d{1,10}\.\d{1,10}\.\d{1,10}-?.{0,50})', package)
    version_string = version_tuple.groups()[0]
    version = version_string.split("-", 1)[1]

    name = re.split('(-\d{1,10}\.\d{1,10}\.\d{1,10}-?.{0,50})', package)
    pkg_name = name[0]
    return(pkg_name, version)


def build_a_pkg_dict(package: str):
    """ For each package get build its dictionary entry """
    # Example string: concurrent-ruby-1.1.8
    try:
        pkg_name, pkg_version = split_name(package)
        
        # Can build the file location and hash location URLs with just this info above
        filename = "{}.gem".format(package)
        pkg_url = "https://rubygems.org/downloads/{}.gem".format(package)
        sha_url = "https://rubygems.org/gems/{}/versions/{}".format(pkg_name, pkg_version)

        pkg_sha, sha_type_string = get_sha(sha_url)
        sha_type = sha_type_string.replace(" ", "")

        # Create pkg dictionary
        pkg_entry = {
            'pkg_filename': filename,
            'sha_url': sha_url,
            'pkg_url': pkg_url,
            'pkg_sha': pkg_sha,
            'sha_type': sha_type  
            }
        success = True
        return(success, pkg_entry)
    except:
        success = False
        return(success, package)


def build_master_pkg_dicts(packages: list):
    """ Build dictionaries with neccessary values and build URLs """
    master_list_pkg_dicts = []
    failed_list = []
    with multiprocessing.Pool(processes=15) as pool:
        vals = pool.imap(build_a_pkg_dict, packages)
        # add packages to master or failed list
        for pkg_tuple in vals:
            success = pkg_tuple[0]
            if success:
                pkg_dict = pkg_tuple[1]
                master_list_pkg_dicts.append(pkg_dict)
            else:
                pkg_name = pkg_tuple[1]
                failed_list.append(pkg_name)
    return(master_list_pkg_dicts, failed_list)


def gem_create_hardening_manifest(force_option: bool, multi_pkg_types: bool):
    """ Main Function """
    # Based on whether were running multiple packages do the gem env check
    if not multi_pkg_types:
        gem_environment_check()

    # Based on if the manifest exists and the options in cli set some required vars
    manifest_exist = os.path.isfile("hardening_manifest/hardening_manifest.yaml")
    if force_option:
        append_to_manifest = False
        if manifest_exist:
            append_to_manifest = True
    else:
        if not multi_pkg_types:
            append_to_manifest = check_for_existing_manifest()
        else:
            append_to_manifest = True

    # Get user's packages
    print("Getting gem packages and their dependencies...\n")
    path = '{}/requirements_files/gem-packages.txt'.format(os.getcwd())
    user_required_pkgs_list = get_requirements(path)

    # Get dependencies
    master_list, failed_list = create_dep_list(user_required_pkgs_list)

    # Gathering metadata required for each package
    master_list_of_metadata, master_failed_list = build_master_pkg_dicts(master_list)
    for entry in failed_list:
        if entry not in master_failed_list:
            master_failed_list.append(entry)

    if not multi_pkg_types:
        print("Creating hardening manifest...\n")

    # Decide whether we need to append to manifest as well as dedup new and existing list if we do
    if append_to_manifest:
        try:
            master_pkgs_metadata = sha_compare_existing_manifest_to_requirements(master_list_of_metadata)
        except:
            pass
    else:
        master_pkgs_metadata = master_list_of_metadata

    # Build the manifest
    manifest_resources_section = generate_resources_section(master_pkgs_metadata, append_to_manifest)
    generate_hardening_manifest(manifest_resources_section)

    # Based on whether this is multiple package managers and if anything failed print to screen.
    if not multi_pkg_types:
        if master_failed_list:
            print('ERROR: Packages not found:')
            for package in master_failed_list:
                print(' - {}'.format(package))
        else:
            print('All packages found!')
        print("\nHardening manifest located at {}/hardening_manifest/hardening_manifest.yaml\n".format(os.getcwd()))
    if multi_pkg_types:
        return (master_failed_list)
