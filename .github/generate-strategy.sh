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
	[16]='latest'
)

GITHUB_ACTIONS=${GITHUB_ACTIONS:-false}

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}/..")")"
BASE_DIRECTORY="$(pwd)"

# Retrieve the PostgreSQL versions for UBI
cd "$BASE_DIRECTORY"/UBI/
for version in */; do
	[[ $version == src/ ]] && continue
	ubi_versions+=("$version")
done
ubi_versions=("${ubi_versions[@]%/}")

# Sort the version numbers with highest first
mapfile -t ubi_versions < <(IFS=$'\n'; sort -rV <<< "${ubi_versions[*]}")

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"
	shift
	local out
	printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

generator() {
	local ubiRelease="$1"; shift

	tagSuffix=""
	if [ "$ubiRelease" -gt "8" ]; then
		tagSuffix="-ubi${ubiRelease}"
	fi

	cd "$BASE_DIRECTORY"/UBI/
	for version in "${ubi_versions[@]}"; do

		versionFile="${version}/.versions-ubi${ubiRelease}.json"
		ubiVersion=$(jq -r '.UBI_VERSION' "${versionFile}")
		fullVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

		# Initial aliases are "major version", "optional alias", "full version with release"
		# i.e. "13", "latest", "13.2-1"
		# A "-beta" suffix will be appended to the beta images.
		if [ "${version}" -gt '16' ]; then
			fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
			versionAliases=(
				"${version}-beta${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}${tagSuffix}"}
				"${fullVersion}-${releaseVersion}${tagSuffix}"
			)
			versionAliasesMultiLang=(
				"${version}-beta-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multilang${tagSuffix}"}
				"${fullVersion}-${releaseVersion}-multilang${tagSuffix}"
			)
			versionAliasesMultiArch=(
				"${version}-beta-multiarch${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multiarch${tagSuffix}"}
				"${fullVersion}-${releaseVersion}-multiarch${tagSuffix}"
			)
		else
			versionAliases=(
				"${version}${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}${tagSuffix}"}
				"${fullVersion}-${releaseVersion}${tagSuffix}"
			)
			versionAliasesMultiLang=(
				"${version}-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multilang${tagSuffix}"}
				"${fullVersion}-${releaseVersion}-multilang${tagSuffix}"
			)
			versionAliasesMultiArch=(
				"${version}-multiarch${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multiarch${tagSuffix}"}
				"${fullVersion}-${releaseVersion}-multiarch${tagSuffix}"
			)
		fi

		# Add all the version prefixes between full version and major version
		# i.e "13.2"
		while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
			versionAliases+=("$fullVersion${tagSuffix}")
			versionAliasesMultiLang+=("$fullVersion-multilang${tagSuffix}")
			versionAliasesMultiArch+=("$fullVersion-multiarch${tagSuffix}")
			fullVersion="${fullVersion%[.-]*}"
		done

		platforms="linux/amd64, linux/arm64"
		platformsMultiArch="${platforms}, linux/ppc64le,linux/s390x"

		# Build the json entry
		entries+=(
			"{\"name\": \"${fullVersion} UBI${ubiRelease}\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.ubi${ubiRelease}\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
			"{\"name\": \"${fullVersion} UBI${ubiRelease} MultiLang\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.multilang.ubi${ubiRelease}\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiLang[@]}")\"]}"
			"{\"name\": \"${fullVersion} UBI${ubiRelease} MultiArch\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platformsMultiArch\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.multiarch.ubi${ubiRelease}\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiArch[@]}")\"]}"
		)
	done
}

generator_postgis() {
	local ubiRelease="$1"; shift

	tagSuffix=""
	if [ "$ubiRelease" -gt "8" ]; then
		tagSuffix="-ubi${ubiRelease}"
	fi

	cd "$BASE_DIRECTORY"/UBI/
	for version in "${ubi_versions[@]}"; do

		# Read versions from the definition file
		versionFile="${version}/.versions-postgis.json"
		fullVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		postgisVersion=$(jq -r '.POSTGIS_VERSION' "${versionFile}" | cut -f1,2 -d.)
		releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

		# Initial aliases are "major version", "optional alias", "full version with release"
		# i.e. "13", "latest", "13.2-1"
		# A "-beta" suffix will be appended to the beta images.
		if [ "${version}" -gt '16' ]; then
			fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
			versionAliases=(
				"${version}-beta-postgis${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis${tagSuffix}"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}${tagSuffix}"
			)
			versionAliasesMultiLang=(
				"${version}-beta-postgis-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis-multilang${tagSuffix}"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang${tagSuffix}"
			)
		else
			versionAliases=(
				"${version}-postgis${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis${tagSuffix}"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}${tagSuffix}"
			)
			versionAliasesMultiLang=(
				"${version}-postgis-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis-multilang${tagSuffix}"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang${tagSuffix}"
			)
		fi

		# Add all the version prefixes between full version and major version
		# i.e "13.2"
		while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
			versionAliases+=("$fullVersion-${postgisVersion}-postgis${tagSuffix}")
			versionAliasesMultiLang+=("$fullVersion-${postgisVersion}-postgis-multilang${tagSuffix}")
			fullVersion="${fullVersion%[.-]*}"
		done

		platforms="linux/amd64,linux/arm64"

		# Build the json entry
		entries+=(
			"{\"name\": \"PostGIS ${fullVersion}-${postgisVersion} UBI${ubiRelease}\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis\",\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
			"{\"name\": \"PostGIS ${fullVersion}-${postgisVersion} UBI${ubiRelease} MultiLang\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis-multilang\",\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiLang[@]}")\"]}"
		)
	done
}

entries=()

# UBI
generator "8"
generator "9"

# UBI PostGIS
generator_postgis "8"

# Build the strategy as a JSON object
strategy="{\"fail-fast\": false, \"matrix\": {\"include\": [$(join ', ' "${entries[@]}")]}}"
jq -C . <<<"$strategy" # sanity check / debugging aid

if [[ "$GITHUB_ACTIONS" == "true" ]]; then
	echo "strategy=$(jq -c . <<<"$strategy")" >> $GITHUB_OUTPUT
fi
