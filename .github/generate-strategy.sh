#!/usr/bin/env bash
#
# Given a list of PostgreSQL versions (defined as directories in the root
# folder of the project), this script generates a JSON object that will be used
# inside the Github workflows as a strategy to create a matrix of jobs to run.
# The JSON object contains, for each PostgreSQL version, the tags of the
# container image to be built.
#

set -eu

# Define an optional aliases for some major versions
declare -A aliases=(
	[13]='latest'
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
	debian_versions+=("$version")
done
debian_versions=("${debian_versions[@]%/}")

# Sort the version numbers with highest first
mapfile -t ubi_versions < <(IFS=$'\n'; sort -rV <<< "${ubi_versions[*]}")
mapfile -t debian_versions < <(IFS=$'\n'; sort -rV <<< "${debian_versions[*]}")

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"
	shift
	local out
	printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

cd "$BASE_DIRECTORY"/UBI/
entries=()
for version in "${ubi_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	versionAliases=(
		"${version}"
		${aliases[$version]:+"${aliases[$version]}"}
		"${fullVersion}"-"${releaseVersion}"
	)

	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion")
		fullVersion="${fullVersion%[.-]*}"
	done

	# Build the json entry
	entries+=(
		"{\"name\": \"UBI ${fullVersion}\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done


cd "$BASE_DIRECTORY"/Debian/

for version in "${debian_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	versionAliases=(
		"debian-${version}"
		${aliases[$version]:+"debian-${aliases[$version]}"}
		"debian-${fullVersion}-${releaseVersion}"
	)

	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("debian-$fullVersion")
		fullVersion="${fullVersion%[.-]*}"
	done

	# Build the json entry
	entries+=(
		"{\"name\": \"Debian ${fullVersion}\", \"dir\": \"Debian/$version\", \"file\": \"Debian/$version/Dockerfile\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done

for version in "${debian_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	versionAliases=(
		"debian-postgis-${version}"
		${aliases[$version]:+"debian-postgis-${aliases[$version]}"}
		"debian-postgis-${fullVersion}-${releaseVersion}"
	)

	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("debian-postgis-$fullVersion")
		fullVersion="${fullVersion%[.-]*}"
	done

	# Build the json entry
	entries+=(
		"{\"name\": \"Debian PostGIS ${fullVersion}\", \"dir\": \"Debian/$version\", \"file\": \"Debian/$version/Dockerfile.postgis\",\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done

# Build the strategy as a JSON object
strategy="{\"fail-fast\": false, \"matrix\": {\"include\": [$(join ', ' "${entries[@]}")]}}"
jq -C . <<<"$strategy" # sanity check / debugging aid
echo "::set-output name=strategy::$(jq -c . <<<"$strategy")"
