#!/usr/local/bin/python3
import sys
import os
import yaml
from .hardening_manifest_functions import *
from .pip_packages import pip_create_hardening_manifest
from .npm_packages import npm_create_hardening_manifest
from .urls import urls_create_hardening_manifest
from .gem_packages import gem_create_hardening_manifest

def all_package_managers(force_option: bool, multi_pkg_types: bool):
    """ Main function for the --all option """
    # This section is checking for an existing manifest.
    if not force_option:
        check_for_existing_manifest()

    # Now we are checking to make sure at least one of the required files has packages in them.
    # Based on which files have packages listed, run the correct function.
    pip_requirements_file_size = os.stat("requirements_files/pip-packages.txt").st_size
    urls_requirements_file_size = os.stat("requirements_files/urls.txt").st_size
    gem_requirements_file_size = os.stat("requirements_files/gem-packages.txt").st_size

    # Make a list of which package manager's requirement files have content so we know what to run
    pkg_managers_to_run = []
    if pip_requirements_file_size != 0:
        pkg_managers_to_run.append("pip")
    if urls_requirements_file_size != 0:
        pkg_managers_to_run.append("urls")
    if gem_requirements_file_size != 0:
        pkg_managers_to_run.append("gem")
    # For npm script to run a project path is required so check for that.
    if "NPM_PROJECT_PATH" in os.environ:
        pkg_managers_to_run.append("npm")


    # If list is empty none had content so exit
    if not pkg_managers_to_run:
        sys.exit('ERROR: No required packages. Please make sure at '
                 'least one of the requirement files in requirements_files/ has content.')

    # Check environments for the package managers trying to be run
    multi_envs_check(pkg_managers_to_run)

    # Run the script for each package manager in the list and get the failed list back.
    has_failed_pkgs = []
    for pkg_manager in pkg_managers_to_run:
        if pkg_manager == "pip":
            failed_pip_list = pip_create_hardening_manifest(force_option, multi_pkg_types)
            if failed_pip_list:
                has_failed_pkgs.append("pip")
        if pkg_manager == "npm":
            failed_npm_list = npm_create_hardening_manifest(force_option, multi_pkg_types)
            if failed_npm_list:
                has_failed_pkgs.append("npm")
        if pkg_manager == "urls":
            failed_urls_list = urls_create_hardening_manifest(force_option, multi_pkg_types)
            if failed_urls_list:
                has_failed_pkgs.append("urls")
        if pkg_manager == "gem":
            failed_gem_list = gem_create_hardening_manifest(force_option, multi_pkg_types)
            if failed_gem_list:
                has_failed_pkgs.append("gem")
        else:
            pass

    # Based on the failed packages lists returned from the above function, print to terminal.
    if has_failed_pkgs:
        for pkg_manager in has_failed_pkgs:
            if pkg_manager == "pip":
                print("\nPip packages not found:")
                for package in failed_pip_list:
                    print(' - {}'.format(package))
            if pkg_manager == "npm":
                print("\nNpm packages not found:")
                for package in failed_npm_list:
                    print(' - {}'.format(package))
            if pkg_manager == "gem":
                print("\nGem packages not found:")
                for package in failed_gem_list:
                    print(' - {}'.format(package))
            if pkg_manager == "urls":
                if failed_urls_list:
                    print("\nUrl packages not found:")
                    for package in failed_urls_list:
                        print(' - {}'.format(package))
    else:
        print('All packages found!')
    print("\nHardening manifest located at {}/hardening_manifest/hardening_manifest.yaml\n".format(os.getcwd()))
