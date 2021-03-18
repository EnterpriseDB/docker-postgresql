#!/usr/bin/env bash
set -eu

declare -A aliases=(
  [13]='latest'
  [9.6]='9'
)

#self="$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}/..")")"

versions=($(ls -d */ | grep -v ^src/))
versions=("${versions[@]%/}")

# sort version numbers with highest first
IFS=$'\n'
versions=($(echo "${versions[*]}" | sort -rV))
unset IFS

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

  fullVersion=$(jq -r '.POSTGRES_VERSION' "${version}/versions.json" | sed -e 's/-.*$//g')
  releaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${version}/versions.json")

  versionAliases=()
  while [ "$fullVersion" != "$version" -a "${fullVersion%[.-]*}" != "$fullVersion" ]; do
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
