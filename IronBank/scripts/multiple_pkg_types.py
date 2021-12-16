#!/usr/local/bin/python3
import yaml
import os
from .hardening_manifest_functions import *
from .pip_packages import pip_create_hardening_manifest
from .npm_packages import npm_create_hardening_manifest
from .urls import urls_create_hardening_manifest
from .gem_packages import gem_create_hardening_manifest

def multi_pkg_type_manifest(force_option: bool, multi_pkg_types: bool, pkg_managers_to_run: list):
    # This section is checking for an existing manifest.
    if not force_option:
        check_for_existing_manifest()

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
                print("\nUrl packages not found:")
                for package in failed_urls_list:
                    print(' - {}'.format(package))
    else:
        print('All packages found!')
    print("\nHardening manifest located at {}/hardening_manifest/hardening_manifest.yaml\n".format(os.getcwd()))
