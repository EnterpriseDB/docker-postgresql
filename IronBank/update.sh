#!/usr/bin/env bash
#
# This script fetches the latest version of each component defined in the
# `versionFile` of every PostgreSQL version present in the root of the project,
# and automatically updates the `versionFile` and the `Dockerfile` when a new
# version is available. If any of the components' version is updated, the
# `ReleaseVersion` of the image will be increased by one.
#

set -Eeuo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

versions=("$@")
if [ ${#versions[@]} -eq 0 ]; then
	for version in $(find  -maxdepth 1 -type d -regex "^./[0-9].*" | sort -n) ; do
		versions+=("$version")
	done
fi
#trim the beginning slash
versions=("${versions[@]%/}") 
#trim the ending slash
versions=("${versions[@]#./}") 
# unused 

# Get the latest UBI base image and use it for IRONBANK # different that what UBI does. TBD change this later after published.
get_latest_ironbank_base() {
	rawContent=$(curl -s -L https://quay.io/api/v1/repository/enterprisedb/edb-ubi/tag/?onlyActiveTags=true)
	echo $rawContent | jq -r '.tags | sort_by(.start_ts) | .[] | select(.is_manifest_list == true) | .name' | tail -n1
}

# Get the latest PostgreSQL minor version package
get_postgresql_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	local base_url="https://yum.postgresql.org"
	if [ "$pg_major" = 15 ]; then
		base_url="$base_url/testing"
	fi

	pgx86_64=$(curl -s -L "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
		perl -ne '/<a.*href="postgresql'"${pg_major/./}"'-server-([^"]+).'"${arch}"'.rpm"/ && print "$1\n"' | \
		sort -rV | head -n1)

	echo ${pgx86_64}

	# For MultiArch images make sure the new package is available for all the architectures before updating
	#if [[ "${version}" =~ ^("11"|"12"|"13")$ ]]; then
	#	pgs390x=$(check_cloudsmith_pkgs "${os_version}" 's390x' "$pg_major")
	#	pgppc64le=$(check_cloudsmith_pkgs "${os_version}" 'ppc64le' "$pg_major")
	#	if [[ ${pgx86_64} != ${pgppc64le} || ${pgx86_64} != ${pgs390x} ]]; then
	#		echo "Version discrepancy between the architectures. Exiting." >&2
	#		echo "x86_64: ${pgx86_64}" >&2
	#		echo "ppc64le: ${pgppc64le}" >&2
	#		echo "s390x: ${pgs390x}" >&2
	#		exit 1
	#	fi
	#fi
}

# cloudsmith not used in this repo

# Get the latest Barman version
latest_barman_version=
_raw_get_latest_barman_version() {
	curl -s https://pypi.org/pypi/barman/json | jq -r '.releases | keys[]' | sort -Vr | head -n1
}
get_latest_barman_version() {
	if [ -z "$latest_barman_version" ]; then
		latest_barman_version=$(_raw_get_latest_barman_version)
	fi
	echo "$latest_barman_version"
}

get_pgaudit_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	local base_url="https://yum.postgresql.org"
	if [ "$pg_major" = 15 ]; then
		base_url="$base_url/testing"
	fi

	case $pg_major in
		9.6) ver=11 ;;
		10) ver=12 ;;
		11) ver=13 ;;
		12) ver=14 ;;
		13) ver=15 ;;
		14) ver=16 ;;
	esac

	pgaudit_version=$(curl -s -L "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
		perl -ne '/<a.*href="pgaudit'"${ver}"_"${pg_major/./}"'-([^"]+).'"${arch}"'.rpm"/ && print "$1\n"' | \
		sort -rV | head -n1)

	echo "${ver}_${pg_major}-${pgaudit_version}"
}

# record_version(versionFile, component, componentVersion)
# Parameters:
#   versionFile: the file containing the version of each component
#   component: the component to be updated
#   componentVersion: the new component version to be set
record_version() {
	local versionFile="$1"; shift
	local component="$1"; shift
	local componentVersion="$1"; shift

	jq -S --arg component "${component}" \
		--arg componentVersion "${componentVersion}" \
		'.[$component] = $componentVersion' <"${versionFile}" >>"${versionFile}.new"

	mv "${versionFile}.new" "${versionFile}"
}

generate_ironbank() {
	local version="$1"; shift
	ironbankRelease="8"
	local versionFile="${version}/.versions.json"

	imageReleaseVersion=1

	# cache the result
	get_latest_ironbank_base >/dev/null
	get_latest_barman_version >/dev/null

	ironbankVersion=$(get_latest_ironbank_base)
	if [ -z "$ironbankVersion" ]; then
		echo "Unable to retrieve latest IRONBANK${ironbankRelease} version"
		exit 1
	fi

	postgresqlVersion=$(get_postgresql_version "${ironbankRelease}" 'x86_64' "$version")
	if [ -z "$postgresqlVersion" ]; then
		echo "Unable to retrieve latest PostgreSQL $version version"
		exit 1
	fi

	barmanVersion=$(get_latest_barman_version)
	if [ -z "$barmanVersion" ]; then
		echo "Unable to retrieve latest Barman version"
		exit 1
	fi

	pgauditVersion=$(get_pgaudit_version "${ironbankRelease}" 'x86_64' "$version")
	if [ -z "$pgauditVersion" ]; then
		echo "Unable to get the pgAudit version"
		exit 1
	fi

	# Output the full Postgresql package name
	echo "$version: ${postgresqlVersion}"

	if [ -f "${versionFile}" ]; then
		oldUbiVersion=$(jq -r '.IRONBANK_VERSION' "${versionFile}")
		oldPostgresqlVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		oldBarmanVersion=$(jq -r '.BARMAN_VERSION' "${versionFile}")
		oldImageReleaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")
		imageReleaseVersion=$oldImageReleaseVersion
	else
		imageReleaseVersion=1

		echo "{}" > "${versionFile}"
		record_version "${versionFile}" "IRONBANK_VERSION" "${ironbankVersion}"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "BARMAN_VERSION" "${barmanVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" "${imageReleaseVersion}"

		return
	fi

	newRelease="false"

	# Detect an update of IRONBANK image
	if [ "$oldUbiVersion" != "$ironbankVersion" ]; then
		echo "IRONBANK changed from $oldUbiVersion to $ironbankVersion"
		newRelease="true"
		record_version "${versionFile}" "IRONBANK_VERSION" "${ironbankVersion}"
	fi

	# Detect an update of Barman
	if [ "$oldBarmanVersion" != "$barmanVersion" ]; then
		echo "Barman changed from $oldBarmanVersion to $barmanVersion"
		newRelease="true"
		record_version "${versionFile}" "BARMAN_VERSION" "${barmanVersion}"
	fi

	# Detect an update of PostgreSQL
	if [ "$oldPostgresqlVersion" != "$postgresqlVersion" ]; then
		echo "PostgreSQL changed from $oldPostgresqlVersion to $postgresqlVersion"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" 1
		imageReleaseVersion=1
	elif [ "$newRelease" = "true" ]; then
		imageReleaseVersion=$((oldImageReleaseVersion + 1))
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" $imageReleaseVersion
	fi

	rm -fr "${version:?}"/*
	sed -e 's/%%IRONBANK_VERSION%%/'"$ironbankVersion"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%PG_MAJOR_NODOT%%/'"${version/./}"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile.template \
		>"$version/Dockerfile"

	# Generates urls.txt file for each PG version. This is used by
	# generate_hardened_manifest.py to set up RPM downloads in IronBank build service
	sed	-e 's/%%PG_MAJOR_NODOT%%/'"${version/./}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		urls.txt.template \
		>"requirements_files/urls.txt"

	cp hardening_manifest.yaml.template hardening_manifest/hardening_manifest.yaml
 	# Add the python requirements and urls to the manifest file used by IronBank
 	python3 generate_hardening_manifest.py -f -p -u 2> /dev/null
    # parse template and copy to version
	sed -e 's/%%IRONBANK_VERSION%%/'"$ironbankVersion"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%PG_MAJOR_NODOT%%/'"${version/./}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		hardening_manifest/hardening_manifest.yaml \
		>"${version}/hardening_manifest.yaml"

	# match the UBI/Debian repo structure
	cp requirements_files/pip-packages.txt src/root/requirements.txt
	cp requirements_files/urls.txt	src/root/urls.txt
	# requirement that certain dirs exist, such as config and scripts
	cp -r src/root/* "${version}/"
}

update_requirements() {
	barmanVersion=$(get_latest_barman_version)
	# If there's a new version we need to recreate the requirements files
	echo "barman[cloud,azure] == $barmanVersion" > requirements.in
	# ugly hack; not very proud of this
	echo "pip == 21.3.1" >> requirements.in

	# This will take the requirements.in file and generate a file
	# requirements.txt with the hashes for the required packages
	# --allow-unsafe is used for pip. This gets re-installed to fix crypto/rust issues
    # --no-annotation is required for IronBank hardening_maifest.yaml conversion
	pip-compile --allow-unsafe --no-annotate --output-file=requirements.txt 2>/dev/null

	# Removes psycopg from the list of packages to install
	sed -i '/psycopg/{:a;N;/barman/!ba};/via barman/d' requirements.txt

	# Then the file needs to be moved into the requirements_files/ that will
	# be used by the generate_hardening_manifest.py program
	# pip-packages.txt is the required format.
	mv requirements.txt requirements_files/pip-packages.txt

}

update_requirements

for version in "${versions[@]}"; do
	generate_ironbank "${version}"
done
