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
		[[ $version =~ (src|image-catalogs) ]] && continue
		versions+=("$version")
	done
fi
versions=("${versions[@]%/}")

# Update this everytime a new major release of PostgreSQL is available
POSTGRESQL_LATEST_MAJOR_RELEASE=17

declare -A lastTagList=()
_raw_ubi_tags() {
	local version="$1"; shift
	local data
	data=$(curl -sL "https://registry.access.redhat.com/v2/ubi${version}/ubi/tags/list")
	jq -r --arg v "$version" '.tags[] | select(startswith($v))' <<<"$data" |
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
	local ubi_version=$1
	rawContent=$(curl -s -L https://quay.io/api/v1/repository/enterprisedb/edb-ubi/tag/?onlyActiveTags=true)
	echo "$rawContent" | jq -r --arg uv "$ubi_version" '.tags | sort_by(.start_ts) | .[] | select(.is_manifest_list == true and (.name | startswith($uv))) | .name' | tail -n1
}

declare -A pgArchMatrix=(
	[x86_64]='pgdg'
	[aarch64]='pgdg'
	[ppc64le]='enterprise'
	[s390x]='edb'
)

# Get the latest PostgreSQL minor version package
get_postgresql_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	local base_url="https://yum.postgresql.org"
	if [ "$pg_major" -gt "${POSTGRESQL_LATEST_MAJOR_RELEASE}" ]; then
		base_url="$base_url/testing"
	fi

	if [[ -z "${pgArchMatrix[$arch]}" ]]; then
		echo "Unsupported architecture." >&2
		return
	fi

	if [[ "${pgArchMatrix[$arch]}" == "pgdg" ]]; then
		latest_pg_version=$(curl -fsSL "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
			perl -ne '/<a.*href="postgresql'"${pg_major}"'-server-([^"]+)-\d+.*.'"${arch}"'.rpm"/ && print "$1\n"' | \
			sort -rV | head -n1)
	fi

	if [[ "${pgArchMatrix[$arch]}" == "edb" ]]; then
		latest_pg_version=$(get_cloudsmith_pgserver_pkg "edb" "${os_version}" "${arch}" "${pg_major}")
	fi

	if [[ "${pgArchMatrix[$arch]}" == "enterprise" ]]; then
		latest_pg_version=$(get_cloudsmith_pgserver_pkg "enterprise" "${os_version}" "${arch}" "${pg_major}")
	fi

	echo "${latest_pg_version}"
}

get_cloudsmith_pgserver_pkg() {
	local repo="$1"; shift
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	cloudsmith ls pkgs enterprisedb/"${repo}" -q "name:postgresql*-server$ distribution:el/${os_version} version:latest architecture:${arch}" -F json 2> /dev/null | \
			jq '.data[].filename' | \
			sed -n 's/.*postgresql'"${pg_major}"'-server-\([0-9]\+.[0-9]\+\)-.*\.'"${arch}"'.*/\1/p' | \
			sort -rV | head -n 1
}

get_cloudsmith_postgis_pkg() {
	local repo="$1"; shift
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	cloudsmith ls pkgs enterprisedb/"${repo}" -q "name:postgis*_${pg_major}$ distribution:el/${os_version} version:latest architecture:${arch}" -F json 2> /dev/null | \
			jq '.data[].filename' | \
			sed -n 's/.*postgis[0-9]\+_'"${pg_major}"'-\([0-9]\+.[0-9]\+.[0-9]\+\)-.*\.'"${arch}"'.*/\1/p' | \
			sort -rV | head -n 1
}

compare_architecture_pkgs() {
	for arg; do
		if [[ "$1" != "$arg" ]]; then
			false; return
		fi
	done

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
		12) pgaudit_version=14 ;;
		13) pgaudit_version=15 ;;
		14) pgaudit_version=16 ;;
		15) pgaudit_version=17 ;;
		16) pgaudit_version=18 ;;
	esac

	echo "$pgaudit_version"
}

# Get the latest PostGIS package
get_postgis_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	if [[ -z "${pgArchMatrix[$arch]}" ]]; then
		echo "Unsupported architecture." >&2
		return
	fi

	local base_url="https://yum.postgresql.org"
	local regexp='postgis\d+_'"${pg_major}"'-(\d+.\d+.\d+)-\d+.*rhel'"${os_version}"'.'"${arch}"'.rpm'

	if [ "$pg_major" -gt "${POSTGRESQL_LATEST_MAJOR_RELEASE}" ]; then
		base_url="$base_url/testing"
		regexp='postgis\d+_'"${pg_major}"'-(\d+.\d+.\d+)-.*.rhel'"${os_version}"'.'"${arch}"'.rpm'
	fi

	if [[ "${pgArchMatrix[$arch]}" == "pgdg" ]]; then
		postgisVersion=$(curl -fsSL "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
			perl -ne '/<a.*href="'"${regexp}"'"/ && print "$1\n"' | \
			sort -rV | head -n1)
	fi

	if [[ "${pgArchMatrix[$arch]}" == "edb" ]]; then
		postgisVersion=$(get_cloudsmith_postgis_pkg "edb" "${os_version}" "${arch}" "${pg_major}")
	fi

	if [[ "${pgArchMatrix[$arch]}" == "enterprise" ]]; then
		postgisVersion=$(get_cloudsmith_postgis_pkg "enterprise" "${os_version}" "${arch}" "${pg_major}")
	fi

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
	local ubiRelease="$1"; shift
	local versionFile="${version}/.versions-ubi${ubiRelease}.json"

	imageReleaseVersion=1

	# cache the result
	get_latest_ubi_base $ubiRelease >/dev/null
	get_latest_barman_version >/dev/null

	ubiVersion=$(get_latest_ubi_base $ubiRelease)
	if [ -z "$ubiVersion" ]; then
		echo "Unable to retrieve latest UBI${ubiRelease} version"
		exit 1
	fi

	pg_x86_64=$(get_postgresql_version "${ubiRelease}" 'x86_64' "$version")
	pg_ppc64le=$(get_postgresql_version "${ubiRelease}" 'ppc64le' "$version")
	pg_s390x=$(get_postgresql_version "${ubiRelease}" 's390x' "$version")
	pg_arm64=$(get_postgresql_version "${ubiRelease}" 'aarch64' "$version")
	if ! compare_architecture_pkgs "$pg_x86_64" "$pg_arm64" "$pg_ppc64le" "$pg_s390x"; then
		echo "Version discrepancy between the architectures of PostgreSQL $version packages in UBI$ubiRelease." >&2
		echo "x86_64: $pg_x86_64" >&2
		echo "arm64: $pg_arm64" >&2
		echo "ppc64le: $pg_ppc64le" >&2
		echo "s390x: $pg_s390x" >&2
		return
	fi

	postgresqlVersion="${pg_x86_64}"
	if [ -z "$postgresqlVersion" ]; then
		echo "Unable to retrieve latest PostgreSQL $version version for UBI$ubiRelease"
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
	if [ "$version" -gt "${POSTGRESQL_LATEST_MAJOR_RELEASE}" ]; then
		yumOptions=" --enablerepo=pgdg${version}-updates-testing"
	fi

	# Output the full Postgresql package name
	echo "$version: ${postgresqlVersion} (UBI${ubiRelease})"

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

	# Update root files
	rm -fr "${version:?}/root" \
		"${version:?}/Dockerfile*${ubiRelease}"
	cp -r src/* "$version/"

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

	# Detect an update of Dockerfile template
	if [[ -n $(git diff --name-status Dockerfile.template Dockerfile-multilang.template Dockerfile-multiarch.template Dockerfile-plv8.template) ]]; then
		echo "Detected update of a Dockerfile template"
		newRelease="true"
	fi

	# Detect an update of requirements.txt
	if [[ -n $(git diff --name-status "$version/root/requirements.txt") ]]; then
		echo "Detected update of requirements.txt dependencies"
		newRelease="true"
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

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile.template \
		>"$version/Dockerfile.ubi${ubiRelease}"

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-multilang.template \
		>"$version/Dockerfile.multilang.ubi${ubiRelease}"

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-multiarch.template \
		>"$version/Dockerfile.multiarch.ubi${ubiRelease}"

	if [ "$version" -ge '15' ]; then
		sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-plv8.template \
		>"$version/Dockerfile.plv8.ubi${ubiRelease}"
	fi
}

generate_redhat_postgis() {
	local version="$1"; shift
	local ubiRelease="$1"; shift
	local versionFile="${version}/.versions-postgis-ubi${ubiRelease}.json"

	imageReleaseVersion=1

	# cache the result
	get_latest_ubi_base $ubiRelease >/dev/null
	get_latest_barman_version >/dev/null

	ubiVersion=$(get_latest_ubi_base $ubiRelease)
	if [ -z "$ubiVersion" ]; then
		echo "Unable to retrieve latest UBI${ubiRelease} version"
		exit 1
	fi

	pg_x86_64=$(get_postgresql_version "${ubiRelease}" 'x86_64' "$version")
	pg_ppc64le=$(get_postgresql_version "${ubiRelease}" 'ppc64le' "$version")
	pg_s390x=$(get_postgresql_version "${ubiRelease}" 's390x' "$version")
	pg_arm64=$(get_postgresql_version "${ubiRelease}" 'aarch64' "$version")
	if ! compare_architecture_pkgs "$pg_x86_64" "$pg_arm64" "$pg_ppc64le" "$pg_s390x"; then
		echo "Version discrepancy between the architectures of PostgreSQL $version packages in UBI$ubiRelease." >&2
		echo "x86_64: $pg_x86_64" >&2
		echo "arm64: $pg_arm64" >&2
		echo "ppc64le: $pg_ppc64le" >&2
		echo "s390x: $pg_s390x" >&2
		return
	fi

	postgresqlVersion="${pg_x86_64}"
	if [ -z "$postgresqlVersion" ]; then
		echo "Unable to retrieve latest PostgreSQL $version version for UBI$ubiRelease"
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

	postgis_x86_64=$(get_postgis_version "${ubiRelease}" 'x86_64' "$version")
	postgis_ppc64le=$(get_postgis_version "${ubiRelease}" 'ppc64le' "$version")
	postgis_s390x=$(get_postgis_version "${ubiRelease}" 's390x' "$version")
	postgis_arm64=$(get_postgis_version "${ubiRelease}" 'aarch64' "$version")
	if ! compare_architecture_pkgs "$postgis_x86_64" "$postgis_arm64" "$postgis_ppc64le" "$postgis_s390x"; then
		echo "Version discrepancy between the architectures of PostGIS $version packages in UBI$ubiRelease." >&2
		echo "x86_64: $postgis_x86_64" >&2
		echo "arm64: $postgis_arm64" >&2
		echo "ppc64le: $postgis_ppc64le" >&2
		echo "s390x: $postgis_s390x" >&2
		return
	fi

	postgisVersion="${postgis_x86_64}"
	if [ -z "$postgisVersion" ]; then
		echo "Unable to get the PostGIS version"
		exit 1
	fi

	postgisMajor=$(echo ${postgisVersion} | cut -f1,2 -d.)
	postgisMajorNoDot=${postgisMajor//./}

	# Unreleased PostgreSQL versions
	yumOptions=""
	if [ "$version" -gt "${POSTGRESQL_LATEST_MAJOR_RELEASE}" ]; then
		yumOptions=" --enablerepo=pgdg${version}-updates-testing"
	fi

	# Output the full Postgresql and PostGIS package name
	echo "$version: ${postgresqlVersion} - PostGIS ${postgisVersion} (UBI${ubiRelease})"

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

	# Detect an update of Dockerfile template
	if [[ -n $(git diff --name-status Dockerfile-postgis.template Dockerfile-postgis-multilang.template Dockerfile-postgis-multiarch.template) ]]; then
		echo "Detected update of a Dockerfile template"
		newRelease="true"
	fi

	# Detect an update of requirements.txt
	if [[ -n $(git diff --name-status "$version/root/requirements.txt") ]]; then
		echo "Detected update of requirements.txt dependencies"
		newRelease="true"
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
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%POSTGIS_VERSION%%/'"$postgisVersion"'/g' \
		-e 's/%%POSTGIS_MAJOR%%/'"$postgisMajorNoDot"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-postgis.template \
		>"$version/Dockerfile.postgis.ubi${ubiRelease}"

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%POSTGIS_VERSION%%/'"$postgisVersion"'/g' \
		-e 's/%%POSTGIS_MAJOR%%/'"$postgisMajorNoDot"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-postgis-multilang.template \
		>"$version/Dockerfile.postgis-multilang.ubi${ubiRelease}"

	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g' \
		-e 's/%%UBI_MAJOR_VERSION%%/'"$ubiRelease"'/g' \
		-e 's/%%PG_MAJOR%%/'"$version"'/g' \
		-e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%PGAUDIT_VERSION%%/'"$pgauditVersion"'/g' \
		-e 's/%%POSTGIS_VERSION%%/'"$postgisVersion"'/g' \
		-e 's/%%POSTGIS_MAJOR%%/'"$postgisMajorNoDot"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-postgis-multiarch.template \
		>"$version/Dockerfile.postgis-multiarch.ubi${ubiRelease}"
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
	generate_redhat "${version}" "8"
	generate_redhat "${version}" "9"
	generate_redhat_postgis "${version}" "8"
	generate_redhat_postgis "${version}" "9"
done
