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
	for version in */; do
		[[ $version = src/ ]] && continue
		versions+=("$version")
	done
fi
versions=("${versions[@]%/}")

declare -A lastTagList=()
_raw_ubi_tags() {
	local version="$1"; shift
	local data
	data=$(curl -sL "https://registry.access.redhat.com/v2/ubi${version}/ubi/tags/list")
	jq -r '.tags[] | select(startswith("'"$version"'"))' <<<"$data" |
		grep -v -- "-source" | sort -rV | head -n 1
}

# Get the latest UBI tag
get_latest_ubi_tag() {
	local version="$1"; shift
	if [ -z "${lastTagList["$version"]:+isset}" ]; then
		local lastTag
		lastTag="$(_raw_ubi_tags "$version")"
		lastTagList["$version"]="$lastTag"
	fi
	echo "${lastTagList["$version"]}"
}

# Get the latest UBI base image
get_latest_ubi_base() {
	rawContent=$(curl -s -L https://quay.io/api/v1/repository/enterprisedb/edb-ubi/tag/?onlyActiveTags=true)
	echo $rawContent | jq -r '.tags | sort_by(.start_ts) | .[] | select(.is_manifest_list == true) | .name' | tail -n1
}

declare -A pgArchMatrix=(
	[x86_64]='pgdg'
	[ppc64le]='enterprise'
	[s390x]='edb'
)

# Get the latest PostgreSQL minor version package
get_postgresql_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	local base_url="https://yum.postgresql.org"
	if [ "$pg_major" -gt '15' ]; then
		base_url="$base_url/testing"
	fi

	if [[ -z "${pgArchMatrix[$arch]}" ]]; then
		echo "Unsupported architecture." >&2
		return
	fi

	if [[ "${pgArchMatrix[$arch]}" == "pgdg" ]]; then
		latest_pg_version=$(curl -fsSL "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
			perl -ne '/<a.*href="postgresql'"${pg_major}"'-server-([^"]+).'"${arch}"'.rpm"/ && print "$1\n"' | \
			sort -rV | head -n1)
	fi

	if [[ "${pgArchMatrix[$arch]}" == "edb" ]]; then
		latest_pg_version=$(check_cloudsmith_pkgs "edb" "${os_version}" "${arch}" "${pg_major}")
	fi

	if [[ "${pgArchMatrix[$arch]}" == "enterprise" ]]; then
		latest_pg_version=$(check_cloudsmith_pkgs "enterprise" "${os_version}" "${arch}" "${pg_major}")
	fi

	echo "${latest_pg_version}"
}

check_cloudsmith_pkgs() {
	local repo="$1"; shift
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	cloudsmith ls pkgs enterprisedb/"${repo}" -q "name:postgresql*-server$ distribution:el/${os_version} version:latest architecture:${arch}" -F json 2> /dev/null | \
			jq '.data[].filename' | \
			sed -n 's/.*postgresql'"${pg_major}"'-server-\([0-9].*\)\.'"${arch}"'.*/\1/p' | \
			sort -V
}


compare_architecture_pkgs() {
	local x86_64="$1"; shift
	local ppc64le="$1"; shift
	local s390x="$1"; shift

	if [[ -z "$x86_64" || -z "$ppc64le" || -z "$s390x" ]]; then
		echo "Unable to retrieve at least one of the multi-arch packages." >&2
		echo "x86_64: ${x86_64}" >&2
		echo "ppc64le: ${ppc64le}" >&2
		echo "s390x: ${s390x}" >&2
		false; return
	fi

	if [[ ${x86_64} != ${ppc64le} || ${x86_64} != ${s390x} ]]; then
		echo "Version discrepancy between the architectures." >&2
		echo "x86_64: ${x86_64}" >&2
		echo "ppc64le: ${ppc64le}" >&2
		echo "s390x: ${s390x}" >&2
		false; return
	fi

	true
}

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
	local pg_major="$1"; shift

	case $pg_major in
		10) pgaudit_version=12 ;;
		11) pgaudit_version=13 ;;
		12) pgaudit_version=14 ;;
		13) pgaudit_version=15 ;;
		14) pgaudit_version=16 ;;
		15) pgaudit_version=17 ;;
	esac

	echo "$pgaudit_version"
}

# Get the latest PostGIS package
get_postgis_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	local base_url="https://yum.postgresql.org"
	local regexp='postgis\d+_'"${pg_major}"'-([\d+\.]+-\d+.rhel'"${os_version}"').'"${arch}"'.rpm'

	if [ "$pg_major" -gt '15' ]; then
		base_url="$base_url/testing"
		regexp='postgis\d+_'"${pg_major}"'-([\d+\.]+-.*.rhel'"${os_version}"').'"${arch}"'.rpm'
	fi

	postgisVersion=$(curl -fsSL "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
		perl -ne '/<a.*href="'"${regexp}"'"/ && print "$1\n"' | \
		sort -rV | head -n1)

	echo "${postgisVersion}"
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

generate_redhat() {
	local version="$1"; shift
	ubiRelease="8"
	local versionFile="${version}/.versions.json"

	imageReleaseVersion=1

	# cache the result
	get_latest_ubi_base >/dev/null
	get_latest_barman_version >/dev/null

	ubiVersion=$(get_latest_ubi_base)
	if [ -z "$ubiVersion" ]; then
		echo "Unable to retrieve latest UBI${ubiRelease} version"
		exit 1
	fi

	pg_x86_64=$(get_postgresql_version "${ubiRelease}" 'x86_64' "$version")

	# Multi arch is available from v11 onwards
	if [ "$version" -gt '10' ]; then
		pg_ppc64le=$(get_postgresql_version "${ubiRelease}" 'ppc64le' "$version")
		pg_s390x=$(get_postgresql_version "${ubiRelease}" 's390x' "$version")

		if ! compare_architecture_pkgs "$pg_x86_64" "$pg_ppc64le" "$pg_s390x"; then
			return
		fi
	fi

	postgresqlVersion="${pg_x86_64}"
	if [ -z "$postgresqlVersion" ]; then
		echo "Unable to retrieve latest PostgreSQL $version version"
		return
	fi

	barmanVersion=$(get_latest_barman_version)
	if [ -z "$barmanVersion" ]; then
		echo "Unable to retrieve latest Barman version"
		exit 1
	fi

	pgauditVersion=$(get_pgaudit_version "$version")
	if [ -z "$pgauditVersion" ]; then
		echo "Unable to get the pgAudit version"
		exit 1
	fi

	# Unreleased PostgreSQL versions
	yumOptions=""
	if [ "$version" -gt '15' ]; then
		yumOptions=" --enablerepo=pgdg${version}-updates-testing"
	fi

	# Output the full Postgresql package name
	echo "$version: ${postgresqlVersion}"

	if [ -f "${versionFile}" ]; then
		oldUbiVersion=$(jq -r '.UBI_VERSION' "${versionFile}")
		oldPostgresqlVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		oldBarmanVersion=$(jq -r '.BARMAN_VERSION' "${versionFile}")
		oldImageReleaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")
		imageReleaseVersion=$oldImageReleaseVersion
	else
		imageReleaseVersion=1

		echo "{}" > "${versionFile}"
		record_version "${versionFile}" "UBI_VERSION" "${ubiVersion}"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "BARMAN_VERSION" "${barmanVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" "${imageReleaseVersion}"

		return
	fi

	newRelease="false"

	# Detect an update of UBI image
	if [ "$oldUbiVersion" != "$ubiVersion" ]; then
		echo "UBI changed from $oldUbiVersion to $ubiVersion"
		newRelease="true"
		record_version "${versionFile}" "UBI_VERSION" "${ubiVersion}"
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
	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile.template \
		>"$version/Dockerfile"

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-multilang.template \
		>"$version/Dockerfile.multilang"
	cp -r src/* "$version/"
}

generate_redhat_postgis() {
	local version="$1"; shift
	ubiRelease="8"
	local versionFile="${version}/.versions-postgis.json"

	imageReleaseVersion=1

	# cache the result
	get_latest_ubi_base >/dev/null
	get_latest_barman_version >/dev/null

	ubiVersion=$(get_latest_ubi_base)
	if [ -z "$ubiVersion" ]; then
		echo "Unable to retrieve latest UBI${ubiRelease} version"
		exit 1
	fi

	postgresqlVersion=$(get_postgresql_version "${ubiRelease}" 'x86_64' "$version")
	if [ -z "$postgresqlVersion" ]; then
		echo "Unable to retrieve latest PostgreSQL $version version"
		return
	fi

	barmanVersion=$(get_latest_barman_version)
	if [ -z "$barmanVersion" ]; then
		echo "Unable to retrieve latest Barman version"
		exit 1
	fi

	pgauditVersion=$(get_pgaudit_version "$version")
	if [ -z "$pgauditVersion" ]; then
		echo "Unable to get the pgAudit version"
		exit 1
	fi

	postgisVersion=$(get_postgis_version "${ubiRelease}" 'x86_64' "$version")
	if [ -z "$postgisVersion" ]; then
		echo "Unable to get the PostGIS version"
		exit 1
	fi

	postgisMajor=$(echo ${postgisVersion} | cut -f1,2 -d.)
	postgisMajorNoDot=${postgisMajor//./}

	# Unreleased PostgreSQL versions
	yumOptions=""
	if [ "$version" -gt '15' ]; then
		yumOptions=" --enablerepo=pgdg${version}-updates-testing"
	fi

	# Output the full Postgresql and PostGIS package name
	echo "$version: ${postgresqlVersion} - PostGIS ${postgisVersion}"

	if [ -f "${versionFile}" ]; then
		oldUbiVersion=$(jq -r '.UBI_VERSION' "${versionFile}")
		oldPostgresqlVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		oldPostgisVersion=$(jq -r '.POSTGIS_VERSION' "${versionFile}")
		oldBarmanVersion=$(jq -r '.BARMAN_VERSION' "${versionFile}")
		oldImageReleaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")
		imageReleaseVersion=$oldImageReleaseVersion
	else
		imageReleaseVersion=1

		echo "{}" > "${versionFile}"
		record_version "${versionFile}" "UBI_VERSION" "${ubiVersion}"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "POSTGIS_VERSION" "${postgisVersion}"
		record_version "${versionFile}" "BARMAN_VERSION" "${barmanVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" "${imageReleaseVersion}"

		return
	fi

	newRelease="false"

	# Detect an update of UBI image
	if [ "$oldUbiVersion" != "$ubiVersion" ]; then
		echo "UBI changed from $oldUbiVersion to $ubiVersion"
		newRelease="true"
		record_version "${versionFile}" "UBI_VERSION" "${ubiVersion}"
	fi

	# Detect an update of Barman
	if [ "$oldBarmanVersion" != "$barmanVersion" ]; then
		echo "Barman changed from $oldBarmanVersion to $barmanVersion"
		newRelease="true"
		record_version "${versionFile}" "BARMAN_VERSION" "${barmanVersion}"
	fi

	if [ "$newRelease" = "true" ]; then
		imageReleaseVersion=$((oldImageReleaseVersion + 1))
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" $imageReleaseVersion
	fi

	# Detect an update of PostgreSQL
	if [ "$oldPostgresqlVersion" != "$postgresqlVersion" ]; then
		echo "PostgreSQL changed from $oldPostgresqlVersion to $postgresqlVersion"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" 1
		imageReleaseVersion=1
	fi

	# Detect an update of PostGIS
	if [ "$oldPostgisVersion" != "$postgisVersion" ]; then
		echo "PostGIS changed from $oldPostgisVersion to $postgisVersion"
		record_version "${versionFile}" "POSTGIS_VERSION" "${postgisVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" 1
		imageReleaseVersion=1
	fi

	cp initdb-postgis.sh "$version/"
	cp update-postgis.sh "$version/"

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%POSTGIS_VERSION%%/'"$postgisVersion"'/g' \
		-e 's/%%POSTGIS_MAJOR%%/'"$postgisMajorNoDot"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-postgis.template \
		>"$version/Dockerfile.postgis"
}

update_requirements() {
	barmanVersion=$(get_latest_barman_version)
	# If there's a new version we need to recreate the requirements files
	echo "barman[cloud,azure,snappy,google] == $barmanVersion" > requirements.in

	# This will take the requirements.in file and generate a file
	# requirements.txt with the hashes for the required packages
	pip-compile --generate-hashes 2> /dev/null

	# Removes psycopg from the list of packages to install
	sed -i '/psycopg/{:a;N;/barman/!ba};/via barman/d' requirements.txt

	# Then the file needs to be moved into the src/root/ that will
	# be added to every container later
	mv requirements.txt src/root
}

update_requirements

for version in "${versions[@]}"; do
	generate_redhat "${version}"
	generate_redhat_postgis "${version}"
done
