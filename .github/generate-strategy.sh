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
	[[ $version =~ (src|image-catalogs) ]] && continue
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

		# FullTags
		fullTag="${fullVersion}-${releaseVersion}${tagSuffix}"
		fullTagMultiLang="${fullVersion}-${releaseVersion}-multilang${tagSuffix}"
		fullTagMultiArch="${fullVersion}-${releaseVersion}-multiarch${tagSuffix}"

		# Initial aliases are "major version", "optional alias", "full version with release"
		# i.e. "13", "latest", "13.2-1"
		# A "-beta" suffix will be appended to the beta images.
		if [ "${version}" -gt '16' ]; then
			fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
			versionAliases=(
				"${version}-beta${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}${tagSuffix}"}
				"${fullTag}"
			)
			versionAliasesMultiLang=(
				"${version}-beta-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multilang${tagSuffix}"}
				"${fullTagMultiLang}"
			)
			versionAliasesMultiArch=(
				"${version}-beta-multiarch${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multiarch${tagSuffix}"}
				"${fullTagMultiArch}"
			)
		else
			versionAliases=(
				"${version}${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}${tagSuffix}"}
				"${fullTag}"
			)
			versionAliasesMultiLang=(
				"${version}-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multilang${tagSuffix}"}
				"${fullTagMultiLang}"
			)
			versionAliasesMultiArch=(
				"${version}-multiarch${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-multiarch${tagSuffix}"}
				"${fullTagMultiArch}"
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

		platforms="linux/amd64,linux/arm64"
		platformsMultiArch="${platforms},linux/ppc64le,linux/s390x"

		# Build the json entry
		entries+=(
			"{\"name\": \"${fullVersion} UBI${ubiRelease}\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.ubi${ubiRelease}\", \"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"], \"fullTag\": \"${fullTag}\"}"
			"{\"name\": \"${fullVersion} UBI${ubiRelease} MultiLang\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.multilang.ubi${ubiRelease}\", \"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}-multilang\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiLang[@]}")\"], \"fullTag\": \"${fullTagMultiLang}\"}"
			"{\"name\": \"${fullVersion} UBI${ubiRelease} MultiArch\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platformsMultiArch\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.multiarch.ubi${ubiRelease}\", \"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}-multiarch\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiArch[@]}")\"], \"fullTag\": \"${fullTagMultiArch}\"}"
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
		versionFile="${version}/.versions-postgis-ubi${ubiRelease}.json"
		ubiVersion=$(jq -r '.UBI_VERSION' "${versionFile}")
		fullVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		postgisVersion=$(jq -r '.POSTGIS_VERSION' "${versionFile}" | cut -f1,2 -d.)
		releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

		# FullTags
		fullTag="${fullVersion}-${postgisVersion}-postgis-${releaseVersion}${tagSuffix}"
		fullTagMultiLang="${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang${tagSuffix}"
		fullTagMultiArch="${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multiarch${tagSuffix}"

		# Initial aliases are "major version", "optional alias", "full version with release"
		# i.e. "13", "latest", "13.2-1"
		# A "-beta" suffix will be appended to the beta images.
		if [ "${version}" -gt '16' ]; then
			fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
			versionAliases=(
				"${version}-beta-postgis${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis${tagSuffix}"}
				"${fullTag}"
			)
			versionAliasesMultiLang=(
				"${version}-beta-postgis-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis-multilang${tagSuffix}"}
				"${fullTagMultiLang}"
			)
			versionAliasesMultiArch=(
				"${version}-beta-postgis-multiarch${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis-multiarch${tagSuffix}"}
				"${fullTagMultiArch}"
			)
		else
			versionAliases=(
				"${version}-postgis${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis${tagSuffix}"}
				"${fullTag}"
			)
			versionAliasesMultiLang=(
				"${version}-postgis-multilang${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis-multilang${tagSuffix}"}
				"${fullTagMultiLang}"
			)
			versionAliasesMultiArch=(
				"${version}-postgis-multiarch${tagSuffix}"
				${aliases[$version]:+"${aliases[$version]}-postgis-multiarch${tagSuffix}"}
				"${fullTagMultiArch}"
			)
		fi

		# Add all the version prefixes between full version and major version
		# i.e "13.2"
		while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
			versionAliases+=("$fullVersion-${postgisVersion}-postgis${tagSuffix}")
			versionAliasesMultiLang+=("$fullVersion-${postgisVersion}-postgis-multilang${tagSuffix}")
			versionAliasesMultiArch+=("$fullVersion-${postgisVersion}-postgis-multiarch${tagSuffix}")
			fullVersion="${fullVersion%[.-]*}"
		done

		platforms="linux/amd64,linux/arm64"
		platformsMultiArch="${platforms},linux/ppc64le,linux/s390x"

		# Build the json entry
		entries+=(
			"{\"name\": \"PostGIS ${fullVersion}-${postgisVersion} UBI${ubiRelease}\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis.ubi${ubiRelease}\",\"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}-postgis\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"], \"fullTag\": \"${fullTag}\"}"
			"{\"name\": \"PostGIS ${fullVersion}-${postgisVersion} UBI${ubiRelease} MultiLang\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platforms\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis-multilang.ubi${ubiRelease}\",\"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}-postgis-multilang\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiLang[@]}")\"], \"fullTag\": \"${fullTagMultiLang}\"}"
			"{\"name\": \"PostGIS ${fullVersion}-${postgisVersion} UBI${ubiRelease} MultiArch\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"$platformsMultiArch\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.postgis-multiarch.ubi${ubiRelease}\",\"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}-postgis-multiarch\", \"tags\": [\"$(join "\", \"" "${versionAliasesMultiArch[@]}")\"], \"fullTag\": \"${fullTagMultiArch}\"}"
		)
	done
}

entries=()

# UBI
generator "8"
generator "9"

# UBI PostGIS
generator_postgis "8"
generator_postgis "9"

# Build the strategy as a JSON object
strategy="{\"fail-fast\": false, \"matrix\": {\"include\": [$(join ', ' "${entries[@]}")]}}"
jq -C . <<<"$strategy" # sanity check / debugging aid

if [[ "$GITHUB_ACTIONS" == "true" ]]; then
	echo "strategy=$(jq -c . <<<"$strategy")" >> $GITHUB_OUTPUT
fi
