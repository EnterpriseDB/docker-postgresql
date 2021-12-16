import os
import subprocess
import json
import time
from .hardening_manifest_functions import *

def npm_environment_check():
    """Check to make sure environment requirements are met"""
    print("\nChecking environment...\n")
    # Checking for npm
    if not shutil.which('npm'):
        sys.exit('ERROR: It seems npm is not installed '
                 'or is not in path, please fix to continue.\n')


def get_dependency_json_object(full_project_path):
    """ Using npm command on the project to get every level of dependency """
    cwd = os.getcwd()
    npm_installed_packages_command = (
        "cd {} && npm list --json && cd {}".format(full_project_path, cwd))
    npm_installed_packages_response = subprocess.check_output(
        npm_installed_packages_command, shell=True)
    npm_installed_packages  = npm_installed_packages_response.decode('utf-8')
    npm_installed_packages_json = json.loads(npm_installed_packages)
    return npm_installed_packages_json['dependencies']


def parse_json_results(npm_json_response):
    """ Take the response from npm and grep for 'resolved' field's value """
    with open("npm_all_deps_and_sub_deps.json", "w") as f:
        file_path = os.getcwd() + "/npm_all_deps_and_sub_deps.json"
        json.dump(npm_json_response, f, indent=4)
        f.close()
    grep_response = subprocess.check_output(['grep', '-i', 'resolved', file_path])
    os.remove(file_path)
    url_list = []
    for url in grep_response.decode('utf-8').split('\n'):
        if len(url) > 0:
            stripped_url = url.replace(',', '').replace(' ', '').replace('"', '').split("resolved:", 1)[1]
            if stripped_url not in url_list:
                url_list.append(stripped_url)
            else:
                pass
        else:
            pass
    return url_list


def create_pkg_dict(url_list):
    """ Using the url get all metadata about pkg """
    failed_pkgs_list = []
    master_pkg_list = []
    for url in url_list:
        type = 'sha256'
        pkg_url = url
        filename = url.rsplit("/", 1)[1].replace(",", "")
        try:
            pkg_sha = sha256_Checksum(url)
            single_pkg_dict = {
                "pkg_filename": filename,
                "pkg_url": pkg_url,
                "sha_type": type,
                "pkg_sha": pkg_sha
            }
            master_pkg_list.append(single_pkg_dict)
            found_pkg = True
        except:
            # Try again because a bad request caused pkgs to be
            # marked as not found when we really had the correct data
            try:
                time.sleep(2)
                pkg_sha = sha256_Checksum(url)
                single_pkg_dict = {
                    "pkg_filename": filename,
                    "pkg_url": pkg_url,
                    "sha_type": type,
                    "pkg_sha": pkg_sha
                }
                master_pkg_list.append(single_pkg_dict)
                found_pkg = True
            except:
                found_pkg = False
                failed_pkgs_list.append("{} from {}".format(filename, url))
        print("  - {}".format(filename))
    return failed_pkgs_list, master_pkg_list


def npm_compare_existing_manifest_to_requirements(package_data_list):
    """ Read in existing manifest and compare those values to what we
    have so we only get information about packages that are not yet
    in the existing manifest. """
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
        for entry in package_data_list:
            if entry['pkg_sha'] not in existing_packages_list:
                new_packages.append(entry)
        return new_packages
    except:
        return package_data_list


def npm_create_hardening_manifest(force_option: bool, multi_pkg_types: bool):
    """ Main function """
    # See what context this is being run in, multiple package managers or just npm.
    if not multi_pkg_types:
        npm_environment_check()

    # Check for existing manifest and based on options set in cli set some variables.
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

    print("Getting npm packages metadata...\n")
    # Get the actual data for packages into a list of dictionaries
    # This will get the project deps from the root of the project using npm
    project_deps = get_dependency_json_object(os.environ['NPM_PROJECT_PATH'])
    # Take the npm json response and parse it to a list of package urls
    url_list = parse_json_results(project_deps)
    # Loop through each url and get the required metadata for the packages
    # Returns a list of dictionaries, each dict is one pkg's metadata
    failed_pkgs_list, master_list_of_pkgs = create_pkg_dict(url_list)

    # If were appending to manifest we need to pull in the existing resources
    # and compare to ours so there are no duplicates.
    if append_to_manifest:
        try:
            unique_pkgs_list = npm_compare_existing_manifest_to_requirements(master_list_of_pkgs)
        except:
            pass
    else:
        unique_pkgs_list = master_list_of_pkgs

    if not multi_pkg_types:
        print("Creating hardening manifest...\n")

    # Build resources section and rest of manifest
    resources_dict_yaml_format = generate_resources_section(unique_pkgs_list, append_to_manifest)
    generate_hardening_manifest(resources_dict_yaml_format)

    # Message to user based on any packages failed to be found
    if not multi_pkg_types:
        if failed_pkgs_list:
            print('Packages not found:')
            for package in failed_pkgs_list:
                print(' - {}'.format(package))
        else:
            pass
        print("\nHardening manifest located at {}/hardening_manifest/hardening_manifest.yaml\n".format(os.getcwd()))
    if multi_pkg_types:
        return failed_pkgs_list
