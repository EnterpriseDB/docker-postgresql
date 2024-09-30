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
	[17]='latest'
)

# Define the current default UBI version
DEFAULT_UBI="8"

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

	cd "$BASE_DIRECTORY"/UBI/
	for version in "${ubi_versions[@]}"; do

		versionFile="${version}/.versions-ubi${ubiRelease}.json"
		ubiVersion=$(jq -r '.UBI_VERSION' "${versionFile}")
		fullVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

		# A "-beta" suffix will be appended to the beta images.
		beta=""
		if [ "${version}" -gt '17' ]; then
			beta="-beta"
			# Split PG beta versions before the underscore
			fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
		fi

		# FullTags
		fullTag="${fullVersion}-${releaseVersion}-ubi${ubiRelease}"
		fullTagMultiLang="${fullVersion}-${releaseVersion}-multilang-ubi${ubiRelease}"
		fullTagMultiArch="${fullVersion}-${releaseVersion}-multiarch-ubi${ubiRelease}"

		if [ "${version}" -ge "15" ]; then
		  fullTagPLV8="${fullVersion}-${releaseVersion}-plv8-ubi${ubiRelease}"
		fi

		# Initial aliases are "major version", "optional alias", "full version with release"
		# i.e. "13", "latest", "13.2-1"
		versionAliases=(
			"${version}${beta}-ubi${ubiRelease}"
			${aliases[$version]:+"${aliases[$version]}-ubi${ubiRelease}"}
			"${fullTag}"
		)
		versionAliasesMultiLang=(
			"${version}${beta}-multilang-ubi${ubiRelease}"
			${aliases[$version]:+"${aliases[$version]}-multilang-ubi${ubiRelease}"}
			"${fullTagMultiLang}"
		)
		versionAliasesMultiArch=(
			"${version}${beta}-multiarch-ubi${ubiRelease}"
			${aliases[$version]:+"${aliases[$version]}-multiarch-ubi${ubiRelease}"}
			"${fullTagMultiArch}"
		)

		if [ "${version}" -ge "15" ]; then
			versionAliasesPLV8=(
				"${version}${beta}-plv8-ubi${ubiRelease}"
				${aliases[$version]:+"${aliases[$version]}-plv8-ubi${ubiRelease}"}
				"${fullTagPLV8}"
			)
		fi

		# If we are on the default distro, add the same tags as above but
		# leaving out the distribution
		if [[ "${ubiRelease}" == "${DEFAULT_UBI}" ]]; then
			versionAliases+=(
				"${version}${beta}"
				${aliases[$version]:+"${aliases[$version]}"}
				"${fullVersion}-${releaseVersion}"
			)
			versionAliasesMultiLang+=(
				"${version}${beta}-multilang"
				${aliases[$version]:+"${aliases[$version]}-multilang"}
				"${fullVersion}-${releaseVersion}-multilang"
			)
			versionAliasesMultiArch+=(
				"${version}${beta}-multiarch"
				${aliases[$version]:+"${aliases[$version]}-multiarch"}
				"${fullVersion}-${releaseVersion}-multiarch"
			)

			if [ "${version}" -ge "15" ]; then
				versionAliasesPLV8=(
					"${version}${beta}-plv8"
					${aliases[$version]:+"${aliases[$version]}-plv8"}
					"${fullVersion}-${releaseVersion}-plv8"
				)
			fi
		fi

		# Add all the version prefixes between full version and major version
		# i.e "13.2"
		while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
			versionAliases+=("$fullVersion-ubi${ubiRelease}")
			versionAliasesMultiLang+=("$fullVersion-multilang-ubi${ubiRelease}")
			versionAliasesMultiArch+=("$fullVersion-multiarch-ubi${ubiRelease}")
			if [[ "${ubiRelease}" == "${DEFAULT_UBI}" ]]; then
				versionAliases+=("$fullVersion")
				versionAliasesMultiLang+=("$fullVersion-multilang")
				versionAliasesMultiArch+=("$fullVersion-multiarch")
			fi
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

		if [ "${version}" -ge "15" ]; then
		  entries+=("{\"name\": \"${fullVersion} UBI${ubiRelease} PLV8\", \"ubi_version\": \"$ubiVersion\", \"platforms\": \"linux/amd64\", \"dir\": \"UBI/$version\", \"file\": \"UBI/$version/Dockerfile.plv8.ubi${ubiRelease}\", \"version\": \"$version\", \"flavor\": \"ubi${ubiRelease}-plv8\", \"tags\": [\"$(join "\", \"" "${versionAliasesPLV8[@]}")\"], \"fullTag\": \"${fullTagPLV8}\"}")
		fi
	done
}

generator_postgis() {
	local ubiRelease="$1"; shift

	cd "$BASE_DIRECTORY"/UBI/
	for version in "${ubi_versions[@]}"; do

		# Read versions from the definition file
		versionFile="${version}/.versions-postgis-ubi${ubiRelease}.json"
		ubiVersion=$(jq -r '.UBI_VERSION' "${versionFile}")
		fullVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		postgisVersion=$(jq -r '.POSTGIS_VERSION' "${versionFile}" | cut -f1,2 -d.)
		releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

		# A "-beta" suffix will be appended to the beta images.
		beta=""
		if [ "${version}" -gt '17' ]; then
			beta="-beta"
			# Split PG beta versions before the underscore
			fullVersion=$(jq -r '.POSTGRES_VERSION | split("_") | .[0]' "${versionFile}")
		fi

		# FullTags
		fullTag="${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-ubi${ubiRelease}"
		fullTagMultiLang="${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang-ubi${ubiRelease}"
		fullTagMultiArch="${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multiarch-ubi${ubiRelease}"

		# Initial aliases are "major version", "optional alias", "full version with release"
		# i.e. "13", "latest", "13.2-1"
		versionAliases=(
			"${version}${beta}-postgis-ubi${ubiRelease}"
			${aliases[$version]:+"${aliases[$version]}-postgis-ubi${ubiRelease}"}
			"${fullTag}"
		)
		versionAliasesMultiLang=(
			"${version}${beta}-postgis-multilang-ubi${ubiRelease}"
			${aliases[$version]:+"${aliases[$version]}-postgis-multilang-ubi${ubiRelease}"}
			"${fullTagMultiLang}"
		)
		versionAliasesMultiArch=(
			"${version}${beta}-postgis-multiarch-ubi${ubiRelease}"
			${aliases[$version]:+"${aliases[$version]}-postgis-multiarch-ubi${ubiRelease}"}
			"${fullTagMultiArch}"
		)

		# If we are on the default distro, add the same tags as above but
		# leaving out the distribution
		if [[ "${ubiRelease}" == "${DEFAULT_UBI}" ]]; then
			versionAliases+=(
				"${version}${beta}-postgis"
				${aliases[$version]:+"${aliases[$version]}-postgis"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}"
			)
			versionAliasesMultiLang+=(
				"${version}${beta}-postgis-multilang"
				${aliases[$version]:+"${aliases[$version]}-postgis-multilang"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multilang"
			)
			versionAliasesMultiArch+=(
				"${version}${beta}-postgis-multiarch"
				${aliases[$version]:+"${aliases[$version]}-postgis-multiarch"}
				"${fullVersion}-${postgisVersion}-postgis-${releaseVersion}-multiarch"
			)
		fi

		# Add all the version prefixes between full version and major version
		# i.e "13.2"
		while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
			versionAliases+=("$fullVersion-${postgisVersion}-postgis-ubi${ubiRelease}")
			versionAliasesMultiLang+=("$fullVersion-${postgisVersion}-postgis-multilang-ubi${ubiRelease}")
			versionAliasesMultiArch+=("$fullVersion-${postgisVersion}-postgis-multiarch-ubi${ubiRelease}")
			if [[ "${ubiRelease}" == "${DEFAULT_UBI}" ]]; then
				versionAliases+=("$fullVersion-${postgisVersion}-postgis")
				versionAliasesMultiLang+=("$fullVersion-${postgisVersion}-postgis-multilang")
				versionAliasesMultiArch+=("$fullVersion-${postgisVersion}-postgis-multiarch")
			fi
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
