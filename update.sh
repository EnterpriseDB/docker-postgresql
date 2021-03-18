#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( $(ls -d */ | grep -v ^src/) )
fi
versions=( "${versions[@]%/}" )

declare -A lastTagList=()
_raw_ubi_tags() {
	local name="$1"; shift
	local data
	data=$(curl -sL "https://registry.access.redhat.com/v2/ubi8/ubi/tags/list")
	jq -r '.tags[] | select(startswith("'"$name"'"))' <<<"$data"
}
get_latest_ubi_tag() {
	local version="$1"; shift
	if [ -z "${lastTagList["$version"]:+isset}" ]; then
		local lastTag
		lastTag="$(_raw_ubi_tags "$version" | grep -v -- "-source" | sort -rV | head -n 1)"
		lastTagList["$version"]="$lastTag"
	fi
	echo "${lastTagList["$version"]}"
}

get_postgresql_version() {
	local os_version="$1"; shift
	local arch="$1"; shift
	local pg_major="$1"; shift

	local base_url="https://yum.postgresql.org"
	if [ "$pg_major" = 14 ]; then
		base_url="$base_url/testing"
	fi

	curl -fsSL "${base_url}/${pg_major}/redhat/rhel-${os_version}-${arch}/" | \
		perl -ne '/<a.*href="postgresql'"${pg_major/./}"'-server-([^"]+).'"${arch}"'.rpm"/ && print "$1\n"' | \
		sort -rV | head -n1
}

get_latest_barman_version() {
	curl -s https://pypi.org/pypi/barman/json | jq -r '.releases | keys[]' | sort -Vr | head -n1
}

record_version() {
    local versionFile="$1"
    local component="$2"
    local componentVersion="$3"

    jq --arg component "${component}" \
       --arg componentVersion "${componentVersion}" \
       '.[$component] = $componentVersion' < "${versionFile}" >> "${versionFile}.new"

    mv "${versionFile}.new" "${versionFile}"
}

generate() {
  local version="$1"
  shift
  ubiRelease="8"

	ubiVersion=$(get_latest_ubi_tag "${ubiRelease}")
	if [ -z "$ubiVersion" ]; then
	    echo "Unable to retrieve latest UBI8 version"
	    exit 1
	fi

	postgresqlVersion=$(get_postgresql_version '8' 'x86_64' "$version")
	if [ -z "$postgresqlVersion" ]; then
	    echo "Unable to retrieve latest PostgreSQL $version version"
	    exit 1
	fi

	barmanVersion=$(get_latest_barman_version)
	if [ -z "$barmanVersion" ]; then
	    echo "Unable to retrieve latest Barman version"
	    exit 1
	fi

	yumOptions=""
	if [ "$version" == 13 ]; then
		yumOptions=" --enablerepo=pgdg${version}-updates-testing"
	fi

  createVersions="false"
  if [ -f "${version}/versions.json" ]; then
      oldUbiVersion=$(jq -r '.UBI_VERSION' "${version}/versions.json")
      oldPostgresqlVersion=$(jq -r '.POSTGRES_VERSION' "${version}/versions.json")
      oldBarmanVersion=$(jq -r '.BARMAN_VERSION' "${version}/versions.json")
      oldImageReleaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${version}/versions.json")
  else
      createVersions="true"
  fi

  rm -fr "${version:?}"/*
  sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g;' \
      -e 's/%%PG_MAJOR%%/'"$version"'/g' \
      -e 's/%%PG_MAJOR_NODOT%%/'"${version/./}"'/g' \
      -e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
      -e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
      -e 's/%%BARMAN_VERSION%%/'"$barmanVersion"'/g' \
      Dockerfile.template \
      > "$version/Dockerfile"
	cp -r src/* "$version/"

  if [ "$createVersions" ]; then
      oldUbiVersion=${ubiVersion}
      oldPostgresqlVersion=${postgresqlVersion}
      oldBarmanVersion=${barmanVersion}

      imageReleaseVersion=1
      oldImageReleaseVersion=$imageReleaseVersion

      echo "{}" > "${version}/versions.json"

      record_version "${version}/versions.json" "UBI_VERSION" "${ubiVersion}"
      record_version "${version}/versions.json" "POSTGRES_VERSION" "${postgresqlVersion}"
      record_version "${version}/versions.json" "BARMAN_VERSION" "${barmanVersion}"
      record_version "${version}/versions.json" "IMAGE_RELEASE_VERSION" "${imageReleaseVersion}"
  fi

  newRelease="false"

  if [ "$oldUbiVersion" != "$ubiVersion" ]; then
      echo "UBI changed from $oldUbiVersion to $ubiVersion"
      newRelease="true"
      record_version "${version}/versions.json" "UBI_VERSION" "${ubiVersion}"
  fi

  if [ "$oldPostgresqlVersion" != "$postgresqlVersion" ]; then
      echo "UBI changed from $oldPostgresqlVersion to $postgresqlVersion"
      newRelease="true"
      record_version "${version}/versions.json" "POSTGRES_VERSION" "${postgresqlVersion}"
  fi

  if [ "$oldBarmanVersion" != "$barmanVersion" ]; then
      echo "UBI changed from $oldBarmanVersion to $barmanVersion"
      newRelease="true"
      record_version "${version}/versions.json" "BARMAN_VERSION" "${barmanVersion}"
  fi

  if [ "$newRelease" == "true" ]; then
      imageReleaseVersion=$((oldImageReleaseVersion + 1))
      record_version "${version}/versions.json" "IMAGE_RELEASE_VERSION" $imageReleaseVersion
  fi
}

for version in "${versions[@]}"; do
    generate "${version}"
done
