#################################################################
###
# copied from repo1.dso.mil/dsop/container-hardening-tools/proof-of-concept/resource_scripts/
# last updated 2021-10-25 by akn
###
#################################################################

#!/usr/local/bin/python3
import os
import sys
import argparse
from scripts.pip_packages import pip_create_hardening_manifest
from scripts.npm_packages import npm_create_hardening_manifest
from scripts.multiple_pkg_types import multi_pkg_type_manifest
from scripts.gem_packages import gem_create_hardening_manifest
from scripts.all_packages import all_package_managers
from scripts.urls import urls_create_hardening_manifest

if __name__ == "__main__":

    # Configure cli options and menu
    PARSER = argparse.ArgumentParser(description=(
        'Generate a hardening manifest using the content of '
        'user supplied requirements files or append new packages added to the '
        'user supplied requirements files to an existing manifest. By default the '
        'program will ask you what you would like to do before '
        'appending to any existing manifest.'))
    PARSER.add_argument('-p', '--pip', action='store_true', help=(
        'Indicates pip packages required. Will be ignored with -a/--all.'))
    PARSER.add_argument('-n', '--npm', action='store_true', help=(
        'Indicates npm packages required. Will be ignored with -a/--all.'))
    PARSER.add_argument('-g', '--gem', action='store_true', help=(
        'Indicates gem packages required. Will be ignored with -a/--all.'))
    PARSER.add_argument('-u', '--urls', action='store_true', help=(
        'Indicates no package manager, uses direct download links.'))
    PARSER.add_argument('-a', '--all', action='store_true', help=(
        'Indicates all files found in the "required_packages_file" directory should be '
        'used to build the hardening manifest.'))
    PARSER.add_argument('-f', '--force', help=(
        'Bypass user input and force the program to append to an existing manifest if present. '
        'Will never overwrite existing manifest data.'), required=False, action="store_true")
    PARSER.add_argument('--platform', action='store', help=(
        'Only integrated for -p/--pip currently. Specifies packages for '
        'other platforms rather than the host OS. See Readme for valid platform values.'))
    PARSER.add_argument('--project_path', action='store', help=(
        'Only used with -n/--npm and -a/--all. Specify absolute path to root of your project. '))
    args = PARSER.parse_args()

    # Arguments handling
    force_option = False
    if args.force:
        force_option = True

    if args.platform:
        os.environ['HARDENING_MANIFEST_TARGET_PLATFORM'] = args.platform

    if args.npm:
        if args.project_path:
            os.environ['NPM_PROJECT_PATH'] = args.project_path
        else:
            sys.exit('\nERROR: --project_path must be set when using -n/--npm\n')

    if args.all:
        multi_pkg_types = True
        if args.project_path:
            os.environ['NPM_PROJECT_PATH'] = args.project_path
        all_package_managers(force_option, multi_pkg_types)
    else:
        # Get what package managers were set in the command. Deleting the force
        # and all options from the list because we dont want them in this list.
        arguments_set = vars(args)
        del arguments_set['force'], arguments_set['all']
        pkg_managers_set_cli = []
        for k, v in arguments_set.items():
            if v:
                pkg_managers_set_cli.append(k)

        # If only one package manager is specified then run that script other wise pass
        # the list of ones specified to the multi_pkg_types function
        if len(pkg_managers_set_cli) == 1:
            if args.pip:
                multi_pkg_types = False
                pip_create_hardening_manifest(force_option, multi_pkg_types)
            if args.npm:
                multi_pkg_types = False
                npm_create_hardening_manifest(force_option, multi_pkg_types)
            if args.urls:
                multi_pkg_types = False
                urls_create_hardening_manifest(force_option)
            if args.gem:
                multi_pkg_types = False
                gem_create_hardening_manifest(force_option, multi_pkg_types)
        elif len(pkg_managers_set_cli) >= 2:
            multi_pkg_types = True
            multi_pkg_type_manifest(force_option, multi_pkg_types, pkg_managers_set_cli)
        else:
            sys.exit('ERROR: No package manager specified, at least one is required (-p/-n/-y/-g | -a).')
