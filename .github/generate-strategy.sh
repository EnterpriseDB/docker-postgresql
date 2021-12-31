#!/usr/bin/env bash
#
# Given a list of PostgreSQL versions (defined as directories in the root
# folder of the project), this script generates a JSON object that will be used
# inside the Github workflows as a strategy to create a matrix of jobs to run.
# The JSON object contains, for each PostgreSQL version, the tags of the
# container image to be built.
#

set -eu
declare BUILD_IRONBANK=false
# Want to get the IronBank during the Continuous Integration step 
# but not during the Continuous Delivery step.
while getopts "i" option; do
	case $option in
		i)
		BUILD_IRONBANK=true
		;; 
	esac
done

# Define an optional aliases for some major versions
declare -A aliases=(
	[14]='latest'
	[9.6]='9'
)

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}/..")")"
BASE_DIRECTORY="$(pwd)"

# Retrieve the PostgreSQL versions for UBI
cd "$BASE_DIRECTORY"/UBI/

for version in */; do
	[[ $version == src/ ]] && continue
	ubi_versions+=("$version")
done
ubi_versions=("${ubi_versions[@]%/}")


# Retrieve the PostgreSQL versions for Debian
cd "$BASE_DIRECTORY"/Debian/
for version in */; do
	[[ $version == src/ ]] && continue
	debian_versions+=("$version")
done
debian_versions=("${debian_versions[@]%/}")

# Retrieve the PostgreSQL versions for IronBank
cd "$BASE_DIRECTORY"/IronBank/
for version in $(find  -maxdepth 1 -type d -regex "^./[0-9].*" | sort -n) ; do
	ironbank_versions+=("$version")
done
#trim the beginning slash
ironbank_versions=("${ironbank_versions[@]#./}")
#trim the ending slash
ironbank_versions=("${ironbank_versions[@]%/}")


# Sort the version numbers with highest first
mapfile -t ubi_versions < <(IFS=$'\n'; sort -rV <<< "${ubi_versions[*]}")
mapfile -t debian_versions < <(IFS=$'\n'; sort -rV <<< "${debian_versions[*]}")
mapfile -t ironbank_versions < <(IFS=$'\n'; sort -rV <<< "${ironbank_versions[*]}")


# prints "$2$1$3$1...$N"
join() {
	local sep="$1"
	shift
	local out
	printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

entries=()
cd "$BASE_DIRECTORY"/UBI/
for version in "${ubi_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	# A "-beta" suffix will be appended to the beta images.
	if [ "${version%%.*}" -gt '14' ]; then
		fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
		versionAliases=(
			"${version}-beta"
			${aliases[$version]:+"${aliases[$version]}"}
			"${fullVersion}-${releaseVersion}"
		)
	else
		versionAliases=(
			"${version}"
			${aliases[$version]:+"${aliases[$version]}"}
			"${fullVersion}"-"${releaseVersion}"
		)
	fi
	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion")
		fullVersion="${fullVersion%[.-]*}"
	done

	if [[ "${version}" =~ ^("9.6"|"10"|"14")$ ]]; then
			platforms="linux/amd64"
	else
			platforms="linux/amd64, linux/ppc64le, linux/s390x"
	fi

	# Build the json entry
	entries+=(
		"{\"name\": \"UBI ${fullVersion}\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done

cd "$BASE_DIRECTORY"/IronBank/
for version in "${ironbank_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	# A "-beta" suffix will be appended to the beta images.
	if [ "${version%%.*}" -gt '14' ]; then
		fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
		versionAliases=(
			"${version}-beta"
			${aliases[$version]:+"${aliases[$version]}"}
			"${fullVersion}-${releaseVersion}"
		)
	else
		versionAliases=(
			"${version}"
			${aliases[$version]:+"${aliases[$version]}"}
			"${fullVersion}"-"${releaseVersion}"
		)
	fi
	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion")
		fullVersion="${fullVersion%[.-]*}"
	done

	# Only 
	platforms="linux/amd64"
	IB_BASE_REGISTRY="registry.access.redhat.com"
	IB_BASE_IMAGE="ubi8"

	# Build the json entry
	if [[ "$BUILD_IRONBANK" == "true" ]]; then
		entries+=(
		"{ \"name\": \"IronBank ${fullVersion}\", 
			\"platforms\": \"$platforms\", 
			\"dir\": \"IronBank/$version\", 
			\"file\": \"IronBank/$version/Dockerfile\", 
			\"version\": \"$version\", 
			\"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"],
			\"build_args\": {\"BASE_REGISTRY\": \"${IB_BASE_REGISTRY}\", \"BASE_IMAGE\": \"${IB_BASE_IMAGE}\"}
		}" )
	fi 
done

cd "$BASE_DIRECTORY"/Debian/

for version in "${debian_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	# A "-beta" suffix will be appended to the beta images.
	if [ "${version}" -gt '14' ]; then
		fullVersion="${fullVersion//'~'/-}"
		versionAliases=(
			"${version}-beta-debian"
			${aliases[$version]:+"${aliases[$version]}-debian"}
			"${fullVersion}-debian-${releaseVersion}"
		)
	else
		versionAliases=(
			"${version}-debian"
			${aliases[$version]:+"${aliases[$version]}-debian"}
			"${fullVersion}-debian-${releaseVersion}"
		)
	fi

	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion-debian")
		fullVersion="${fullVersion%[.-]*}"
	done

	platforms="linux/arm64, linux/amd64"

	# Build the json entry
	entries+=(
		"{\"name\": \"Debian ${fullVersion}\", \"platforms\": \"$platforms\", \"dir\": \"Debian/$version\", \"file\": \"Debian/$version/Dockerfile\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done

for version in "${debian_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	# A "-beta" suffix will be appended to the beta images.
	if [ "${version}" -gt '14' ]; then
		fullVersion="${fullVersion//'~'/-}"
		versionAliases=(
			"${version}-beta-debian-postgis"
			${aliases[$version]:+"${aliases[$version]}-debian-postgis"}
			"${fullVersion}-debian-postgis-${releaseVersion}"
		)
	else
		versionAliases=(
			"${version}-debian-postgis"
			${aliases[$version]:+"${aliases[$version]}-debian-postgis"}
			"${fullVersion}-debian-postgis-${releaseVersion}"
		)
	fi

	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion-debian-postgis")
		fullVersion="${fullVersion%[.-]*}"
	done

	platforms="linux/amd64, linux/arm64"

	# Build the json entry
	entries+=(
		"{\"name\": \"Debian PostGIS ${fullVersion}\", \"platforms\": \"$platforms\", \"dir\": \"Debian/$version\", \"file\": \"Debian/$version/Dockerfile.postgis\",\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done

# Build the strategy as a JSON object
strategy="{\"fail-fast\": false, \"matrix\": {\"include\": [$(join ', ' "${entries[@]}")]}}"
jq -C . <<<"$strategy" # sanity check / debugging aid
echo "::set-output name=strategy::$(jq -c . <<<"$strategy")"
