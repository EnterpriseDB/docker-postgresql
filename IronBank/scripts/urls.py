import os
from .pip_packages import get_requirements
from .hardening_manifest_functions import *


def urls_environment_check():
    print("\nChecking Environment...")
    # Make sure urls.txt has content
    file_size = os.stat("requirements_files/urls.txt")
    if file_size.st_size == 0:
        sys.exit('\nERROR: urls.txt does not have any content.'
                 ' Please add required packages urls there.\n')


def get_package_metadata(requirements_list):
    """ Using the url get the hash of remote file and build package's dictionary """
    print("\nGetting metadata for {} package urls...".format(len(requirements_list)))
    master_failed_list = []
    master_list_of_dicts = []
    for pkg_url in requirements_list:
        try:
            pkg_sha = sha256_Checksum(pkg_url)
            filename = pkg_url.rsplit("/", 1)[1]
            pkg_entry = {
                'pkg_filename': filename,
                'pkg_url': pkg_url,
                'pkg_sha': pkg_sha,
                'sha_type': "sha256"
            }
            master_list_of_dicts.append(pkg_entry)
            print("    - {}".format(filename))
        except:
            master_failed_list.append(pkg_url)
    return master_failed_list, master_list_of_dicts


def urls_create_hardening_manifest(force_option, multi_pkg_types):
    """ main function to build manifest """
    # Make sure urls.txt has content
    if not multi_pkg_types:
        urls_environment_check()

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

    # Get the supplied file into a list of packages
    path = '{}/requirements_files/urls.txt'.format(os.getcwd())
    print("Gathering required packages...")
    requirements_list = get_requirements(path)

    # Build dictionary entry for each package and put them all in a list
    master_failed_list, master_list_of_dicts = get_package_metadata(requirements_list)

    # Decide whether we need to append to manifest as well as dedup new and existing list if we do
    if append_to_manifest:
        try:
            master_pkgs_metadata = sha_compare_existing_manifest_to_requirements(master_list_of_dicts)
        except:
            pass
    else:
        master_pkgs_metadata = master_list_of_dicts

    if not multi_pkg_types:
        print("\nCreating hardening manifest...\n")

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

    
