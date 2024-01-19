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

entries=()

# UBI
cd "$BASE_DIRECTORY"/UBI/
for version in "${ubi_versions[@]}"; do

	# Read versions from the definition file
	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")
	ubi8Version=$(jq -r '.UBI8_VERSION' "${versionFile}")
  ubi9Version=$(jq -r '.UBI9_VERSION' "${versionFile}")

	# Initial aliases are "major version", "optional alias", "full version with release"
	# i.e. "13", "latest", "13.2-1"
	# A "-beta" suffix will be appended to the beta images.
	if [ "${version}" -gt '16' ]; then
		fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
		versionAliases=(
			"${version}-beta"
			${aliases[$version]:+"${aliases[$version]}"}
			"${fullVersion}-${releaseVersion}"
		)
		versionAliasesMultiLang=(
			"${version}-beta-multilang"
			${aliases[$version]:+"${aliases[$version]}-multilang"}
			"${fullVersion}-${releaseVersion}-multilang"
		)
		versionAliasesMultiArch=(
			"${version}-beta-multiarch"
			${aliases[$version]:+"${aliases[$version]}-multiarch"}
			"${fullVersion}-${releaseVersion}-multiarch"
		)
	else
		versionAliases=(
			"${version}"
			${aliases[$version]:+"${aliases[$version]}"}
			"${fullVersion}-${releaseVersion}"
		)
		versionAliasesMultiLang=(
			"${version}-multilang"
			${aliases[$version]:+"${aliases[$version]}-multilang"}
			"${fullVersion}-${releaseVersion}-multilang"
		)
		versionAliasesMultiArch=(
			"${version}-multiarch"
			${aliases[$version]:+"${aliases[$version]}-multiarch"}
			"${fullVersion}-${releaseVersion}-multiarch"
		)
	fi
	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion")
		versionAliasesMultiLang+=("$fullVersion-multilang")
		versionAliasesMultiArch+=("$fullVersion-multiarch")
		fullVersion="${fullVersion%[.-]*}"
	done

	platforms="linux/amd64, linux/arm64"
	platformsMultiArch="${platforms}, linux/ppc64le,linux/s390x"

	# Build the json entry
	for ubiVersion in "$ubi8Version" "$ubi9Version"; do
	  entries+=(
		  "{\"name\": \"UBI${ubiVersion} ${fullVersion}\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
		  "{\"name\": \"UBI${ubiVersion} ${fullVersion} MultiLang\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.multilang\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiLang[@]}")\"]}"
		  "{\"name\": \"UBI${ubiVersion} ${fullVersion} MultiArch\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platformsMultiArch\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.multiarch\", \"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiArch[@]}")\"]}"
	  )
	done
done

# UBI PostGIS
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
			"${version}-beta-postgis"
			${aliases[$version]:+"${aliases[$version]}-postgis"}
			"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}"
		)
		versionAliasesMultiLang=(
			"${version}-beta-postgis-multilang"
			${aliases[$version]:+"${aliases[$version]}-postgis-multilang"}
			"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang"
		)
	else
		versionAliases=(
			"${version}-postgis"
			${aliases[$version]:+"${aliases[$version]}-postgis"}
			"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}"
		)
		versionAliasesMultiLang=(
			"${version}-postgis-multilang"
			${aliases[$version]:+"${aliases[$version]}-postgis-multilang"}
			"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang"
		)
	fi

	# Add all the version prefixes between full version and major version
	# i.e "13.2"
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("$fullVersion-${postgisVersion}-postgis")
		versionAliasesMultiLang+=("$fullVersion-${postgisVersion}-postgis-multilang")
		fullVersion="${fullVersion%[.-]*}"
	done

	platforms="linux/amd64,linux/arm64"

	# Build the json entry
	entries+=(
		"{\"name\": \"UBI PostGIS ${fullVersion}-${postgisVersion}\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis\",\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
		"{\"name\": \"UBI PostGIS ${fullVersion}-${postgisVersion} MultiLang\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis-multilang\",\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiLang[@]}")\"]}"
	)
done

# Build the strategy as a JSON object
strategy="{\"fail-fast\": false, \"matrix\": {\"include\": [$(join ', ' "${entries[@]}")]}}"
jq -C . <<<"$strategy" # sanity check / debugging aid

if [[ "$GITHUB_ACTIONS" == "true" ]]; then
	echo "strategy=$(jq -c . <<<"$strategy")" >> $GITHUB_OUTPUT
fi
