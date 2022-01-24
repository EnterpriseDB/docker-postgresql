#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=("$@")
if [ ${#versions[@]} -eq 0 ]; then
	for version in */; do
		[[ $version = src/ ]] && continue
		versions+=("$version")
	done
fi
versions=("${versions[@]%/}")

defaultDebianSuite='buster-slim'
declare -A debianSuite=(
	# https://github.com/docker-library/postgres/issues/582
	# [10]='stretch-slim'
	# [11]='stretch-slim'
)

packagesBase='http://apt.postgresql.org/pub/repos/apt/dists/'
declare -A suitePackageList=() suiteVersionPackageList=() suiteArches=()

_raw_package_list() {
	local suite="$1"; shift
	local component="$1"; shift
	local arch="$1"; shift

	curl -fsSL "$packagesBase/$suite-pgdg/$component/binary-$arch/Packages.bz2" | bunzip2
}

fetch_suite_package_list() {
	local suite="$1"; shift
	local version="$1"; shift
	local arch="$1"; shift

	# normal (GA) releases end up in the "main" component of upstream's repository
	if [ -z "${suitePackageList["$suite-$arch"]:+isset}" ]; then
		local suiteArchPackageList
		suiteArchPackageList="$(_raw_package_list "$suite" 'main' "$arch")"
		suitePackageList["$suite-$arch"]="$suiteArchPackageList"
	fi

	# ... but pre-release versions (betas, etc) end up in the "PG_MAJOR" component (so we need to check both)
	if [ -z "${suiteVersionPackageList["$suite-$version-$arch"]:+isset}" ]; then
		local versionPackageList
		versionPackageList="$(_raw_package_list "$suite" "$version" "$arch")"
		suiteVersionPackageList["$suite-$version-$arch"]="$versionPackageList"
	fi
}

awk_package_list() {
	local suite="$1"; shift
	local version="$1"; shift
	local arch="$1"; shift

	awk -F ': ' -v version="$version" "$@" <<<"${suitePackageList["$suite-$arch"]}"$'\n'"${suiteVersionPackageList["$suite-$version-$arch"]}"
}

fetch_suite_arches() {
	local suite="$1"; shift

	if [ -z "${suiteArches["$suite"]:+isset}" ]; then
		local suiteRelease
		suiteRelease="$(curl -fsSL "$packagesBase/$suite-pgdg/Release")"
		suiteArches["$suite"]="$(gawk <<<"$suiteRelease" -F ':[[:space:]]+' '$1 == "Architectures" { print $2; exit }')"
	fi
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

generate_debian() {
	local version="$1"; shift
	tag="${debianSuite[$version]:-$defaultDebianSuite}"
	suite="${tag%%-slim}"
	versionFile="${version}/.versions.json"

	imageReleaseVersion=1

	fetch_suite_package_list "$suite" "$version" 'amd64'
	fullVersion="$(
		awk_package_list "$suite" "$version" 'amd64' '
			$1 == "Package" { pkg = $2 }
			$1 == "Version" && pkg == "postgresql-" version { print $2; exit }
		'
	)"
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: missing postgresql-$version package!"
		exit 1
	fi

	fetch_suite_arches "$suite"
	versionArches=
	for arch in ${suiteArches["$suite"]}; do
		fetch_suite_package_list "$suite" "$version" "$arch"
		archVersion="$(
			awk_package_list "$suite" "$version" "$arch" '
				$1 == "Package" { pkg = $2 }
				$1 == "Version" && pkg == "postgresql-" version { print $2; exit }
			'
		)"
		if [ "$archVersion" = "$fullVersion" ]; then
			[ -z "$versionArches" ] || versionArches+=' | '
			versionArches+="$arch"
		fi
	done

	barmanVersion=$(get_latest_barman_version)

	echo "$version: $fullVersion ($versionArches)"
	postgresqlVersion=$fullVersion

	if [ -f "${versionFile}" ]; then
		oldPostgresqlVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		oldImageReleaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")
		oldBarmanVersion=$(jq -r '.BARMAN_VERSION' "${versionFile}")
		imageReleaseVersion=$oldImageReleaseVersion
	else
		imageReleaseVersion=1

		echo "{}" > "${versionFile}"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" "${imageReleaseVersion}"
		record_version "${versionFile}" "BARMAN_VERSION" "${barmanVersion}"

		exit 1
	fi

	newRelease="false"

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

	cp -r src/* "$version/"
	cp initdb-postgis.sh "$version/"
	cp update-postgis.sh "$version/"

	sed -e 's/%%PG_MAJOR%%/'"$version"'/g;' \
		-e 's/%%PG_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%DEBIAN_TAG%%/'"$tag"'/g' \
		-e 's/%%DEBIAN_SUITE%%/'"$suite"'/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-debian.template \
		> "$version/Dockerfile"

	sed -e 's/%%PG_MAJOR%%/'"$version"'/g;' \
		-e 's/%%PG_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%DEBIAN_TAG%%/'"$tag"'/g' \
		-e 's/%%DEBIAN_SUITE%%/'"$suite"'/g' \
		-e 's/%%POSTGIS_MAJOR%%/"3"/g' \
		-e 's/%%IMAGE_RELEASE_VERSION%%/'"$imageReleaseVersion"'/g' \
		Dockerfile-postgis.template \
		> "$version/Dockerfile.postgis"
}

update_requirements() {
	barmanVersion=$(get_latest_barman_version)
	# If there's a new version we need to recreate the requirements files
	echo "barman[cloud,azure,snappy] == $barmanVersion" > requirements.in

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
	generate_debian "${version}"
done
