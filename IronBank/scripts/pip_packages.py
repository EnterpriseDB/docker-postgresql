#!/usr/local/bin/python3
import os
import re
import sys
import shutil
import tempfile
import multiprocessing
from subprocess import run
import subprocess
from .hardening_manifest_functions import *
import requests

def pip_environment_check():
    """Check to make sure environment requirements are met"""
    print("\nChecking environment...\n")
    # Checking for pip
    try:
        grepOut = subprocess.check_output("python3 -m pip", shell=True)
    except subprocess.CalledProcessError as grepexc:
        sys.exit('ERROR: It seems pip3 is not installed '
                 'or is not in path, "python3 -m pip ..." needs to run. Please fix to continue.\n')
        #print("error code", grepexc.returncode)#, grepexc.output)

    # Make sure pip-packages.txt has content
    file_size = os.stat("requirements_files/pip-packages.txt")
    if file_size.st_size == 0:
        sys.exit('ERROR: pip-packages.txt does not have any content.'
                 ' Please add required packages there.\n')

    # Check connection to https://pypi.org/
    try:
        req = requests.head("https://pypi.org/") # verify=False
    except requests.exceptions.Timeout:
        print("ERROR: Unable to connect to pypi.org\n")
    except requests.exceptions.TooManyRedirects:
        print("ERROR: Unable to connect to pypi.org\n")
    except requests.exceptions.RequestException as exception:
        print("ERROR: Unable to connect to pypi.org\n")
        raise SystemExit(exception)

def get_requirements(path):
    """ Import user's requirement file and save as a variable """
    user_requirements_list = []
    with open(path, 'r') as filehandler:
        user_requirements_list = [package_name.rstrip() for package_name in filehandler.readlines()]
    return user_requirements_list

def get_filenames(requirement: str):
    """ Use pip to build wheel files and their dependencies """
    dependencies_not_found = ''
    with tempfile.TemporaryDirectory() as tmpdirname:
        # The pip download command will get the package and its dependencies.
        # We can use this to create a list of file names from each package's directory.
        # pip download also allows us to specify a target platform if the platform var exists use that cmd.
        platform = os.environ.get('HARDENING_MANIFEST_TARGET_PLATFORM')
        if platform:
            find_dependencies_command = 'python3 -m pip download --platform {} {} --only-binary=:all: -d {} > /dev/null 2>&1'.format(platform, requirement, tmpdirname)
        else:
            find_dependencies_command = 'python3 -m pip download {} --only-binary=:all: -d {} > /dev/null 2>&1'.format(requirement, tmpdirname)
        run(find_dependencies_command, check=False, shell=True)
        dir_list = os.listdir(tmpdirname)
        # If the output directory of the pip command has files in it then
        # return package was found (True) and the list of all files in the
        # directory to add to the master list.
        if dir_list:
            return(True, dir_list, dependencies_not_found)
        else:
            # if pip fails to download the dependencies the command fails and we just try to grab the actual requirement.
            # if platform is set we re-run with option --no-dep so it wont fail this time.
            # if platform is not set re-run with --no-deps and then try the pip wheel command for the dependencies because pip
            # wheel command does not allow the --platform flag.
            if platform:
                get_main_package_command = 'python3 -m pip download --platform {} {} --no-deps -d {} > /dev/null 2>&1'.format(platform, requirement, tmpdirname)
                run(get_main_package_command, check=False, shell=True)
                dir_list = os.listdir(tmpdirname)
                if dir_list:
                    dependencies_not_found = requirement
                    return(True, dir_list, dependencies_not_found)
            if not platform:
                get_main_package_command = 'python3 -m pip download {} --no-deps -d {} > /dev/null 2>&1'.format(requirement, tmpdirname)
                get_deps_command = 'python3 -m pip wheel -q \"{}\" -w {} 2> /dev/null'.format(requirement, tmpdirname)
                run(get_main_package_command, check=False, shell=True)
                run(get_deps_command, check=False, shell=True)
                dir_list = os.listdir(tmpdirname)
                if dir_list:
                    return(True, dir_list, dependencies_not_found)
                else:
                    return(False, requirement)
    return(False, requirement)

def get_package_data(file_name: str):
    """ For each filename in the master list make a request
    to its directory on pypi.org returning needed metadata. """
    pkg_name = re.split('-\d{1,10}\.\d{1,10}\.?-?\d{0,10}-?\.?', file_name)[0]
    package_url = 'https://pypi.org/simple/{}/'.format(pkg_name)
    package_data = {}
    try:
        req = requests.get(package_url)
        response = req.content
        response_list = response.splitlines()
    except:
        package_data = {
            'filename': file_name,
            'pkg_data': 'failed'
            }
        return package_data
    for entry in response_list:
        entry = str(entry)
        # The request returns all versions of the package, find the specific version we need
        if file_name in entry:
            package_data = {
                'filename': file_name,
                'pkg_data': entry
            }
            return package_data
        else:
            pass

    if package_data.get('filename') is not None and package_data.get('pkg_data') is not None:
        return package_data
    else:
        package_data = {
            'filename': file_name,
            'pkg_data': 'failed'
            }
        return package_data

def format_pkg_data(master_package_data: list):
    """ Format and parse the reponse from pypi.org so we can build a dictionary of needed data for
    each package. Example response string (pkg_data variable below) looks like this:
    b'    <a href="https://files.pythonhosted.org/packages/9f/a5/eec74d8d1016e6c2042ba31ca6fba3bb
    a520e27d8a061e82bccd36bd64ef/docker-4.4.1-py2.py3-none-any.whl#sha256=e455fa49aabd4f22da9f4e1
    c1f9d16308286adc60abaf64bf3e1feafaed81d06" data-requires-python="&gt;=2.7, !=3.0.*, !=3.1.*,
    !=3.2.*, !=3.3.*, !=3.4.*">docker-4.4.1-py2.py3-none-any.whl</a><br/>' """
    formatted_package_data = []
    for pkg_dict in master_package_data:
        filename = pkg_dict['filename']
        pkg_data = pkg_dict['pkg_data']

        pkg_url_and_sha = pkg_data.split('"')[1]
        pkg_sha_with_extra_characters = pkg_url_and_sha.split('#')[1]

        pkg_sha = pkg_sha_with_extra_characters.split('=')[1]
        pkg_url = pkg_url_and_sha.split('#')[0]
        sha_type = "sha256"
        formatted_pkg = {
            'pkg_filename': filename,
            'pkg_url': pkg_url,
            'pkg_sha': pkg_sha,
            'sha_type': sha_type
        }
        formatted_package_data.append(formatted_pkg)
    return formatted_package_data

def pip_create_hardening_manifest(force_option: bool, multi_pkg_types: bool):
    """ Main function """
    if not multi_pkg_types:
        pip_environment_check()

    if force_option:
        append_to_manifest = False
        manifest_exist = os.path.isfile("hardening_manifest/hardening_manifest.yaml")
        if manifest_exist:
            append_to_manifest = True
    else:
        if not multi_pkg_types:
            append_to_manifest = check_for_existing_manifest()
        else:
            append_to_manifest = True
    
    path = '{}/requirements_files/pip-packages.txt'.format(os.getcwd())
    user_requirements_list = get_requirements(path)

    print("Getting pip packages and their dependencies...\n")
    dependencies_not_found = []
    master_req_and_dep_list = []
    failed_list = []
    with multiprocessing.Pool(processes=15) as pool:
        vals = pool.imap(get_filenames, user_requirements_list)
        for package_info in vals:
            package_found = package_info[0]
            if package_found:
                dir_list = package_info[1]
                no_deps = package_info[2]
                if no_deps:
                    dependencies_not_found.append(no_deps)
                for file_name in dir_list:
                    if file_name not in master_req_and_dep_list:
                        master_req_and_dep_list.append(file_name)
            else:
                failed_package = package_info[1]
                failed_list.append(failed_package)

    # If there is an existing manifest and the user wants to append new packages to it,
    # append_to_manifest value is based on their answer in the command line.
    if append_to_manifest:
        try:
            master_req_and_dep_list = compare_existing_manifest_to_requirements(master_req_and_dep_list)
        except:
            pass
    else:
        pass

    print("Retrieving metadata about pip packages...\n")
    master_package_data = []
    with multiprocessing.Pool(processes=15) as pool:
        vals = pool.imap(get_package_data, master_req_and_dep_list)
        for package_info in vals:
            if package_info['pkg_data'] != 'failed' and package_info['filename'] not in master_package_data:
                master_package_data.append(package_info)
            if package_info['pkg_data'] == 'failed':
                failed_list.append(package_info['filename'])

    if not multi_pkg_types:
        print("Creating hardening manifest...\n")

    formatted_pkg_data = format_pkg_data(master_package_data)
    resources_dict_yaml_format = generate_resources_section(formatted_pkg_data, append_to_manifest)
    generate_hardening_manifest(resources_dict_yaml_format)

    if dependencies_not_found:
        print("WARNING: When using the --platform option pip may fail to find cross platform dependencies. "
              "The package was most likely added to your manifest without its dependencies "
              "unless a failed packages list containing your package is printed to the cli.\n"
              "\nCould not find the following package(s) dependencies:")
        for pkg in dependencies_not_found:
            print(' - {}'.format(str(pkg)))
        print(" ")

    if not multi_pkg_types:
        if failed_list:
            print('Packages not found:')
            for package in failed_list:
                print(' - {}'.format(package))
        else:
            print('All packages found!')
        print("\nHardening manifest located at {}/hardening_manifest/hardening_manifest.yaml\n".format(os.getcwd()))
    if multi_pkg_types:
        return failed_list
