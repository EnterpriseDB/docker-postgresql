#!/usr/bin/env bash
set -eu

declare -A aliases=(
	[13]='latest'
	[9.6]='9'
)

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}/..")")"

for version in */; do
	[[ $version == src/ ]] && continue
	versions+=("$version")
done
versions=("${versions[@]%/}")

# sort version numbers with highest first
mapfile -t versions < <(IFS=$'\n'; sort -rV <<< "${versions[*]}")

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"
	shift
	local out
	printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

entries=()
for version in "${versions[@]}"; do

	versionFile="${version}/.versions.json"
	fullVersion=$(jq -r '.POSTGRES_VERSION | split("-") | .[0]' "${versionFile}")
	releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")

	versionAliases=()
	while [ "$fullVersion" != "$version" ] && [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=("${fullVersion}"-"${releaseVersion}")
		fullVersion="${fullVersion%[.-]*}"
	done

	versionAliases+=(
		"${version}"
		${aliases[$version]:+"${aliases[$version]}"}
	)

	entries+=(
		"{\"version\": \"$version\", \"tags\": [\"$(join "\", \"" "${versionAliases[@]}")\"]}"
	)
done

strategy="{\"fail-fast\": false, \"matrix\": {\"include\": [$(join ', ' "${entries[@]}")]}}"
jq -C . <<<"$strategy" # sanity check / debugging aid
echo "::set-output name=strategy::$(jq -c . <<<"$strategy")"
