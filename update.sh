#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

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

for version in "${versions[@]}"; do
	ubiVersion=$(get_latest_ubi_tag "8")
	postgresqlVersion=$(get_postgresql_version '8' 'x86_64' "$version")
	barmanVersion=$(get_latest_barman_version)

	yumOptions=""
	if [ "$version" == 13 ]; then
		yumOptions=" --enablerepo=pgdg${version}-updates-testing"
	fi

	echo "$version: $postgresqlVersion"

	rm -fr "$version"/*
	sed -e 's/%%UBI_VERSION%%/'"$ubiVersion"'/g;' \
	    -e 's/%%PG_MAJOR%%/'"$version"'/g' \
	    -e 's/%%PG_MAJOR_NODOT%%/'"${version/./}"'/g' \
	    -e 's/%%YUM_OPTIONS%%/'"${yumOptions}"'/g' \
		-e 's/%%POSTGRES_VERSION%%/'"$postgresqlVersion"'/g' \
		-e 's/%%BARMAN_VERSION%%/'"$barmanVersion"'/g' \
		Dockerfile.template \
		> "$version/Dockerfile"
	cp -r src/* "$version/"
done
