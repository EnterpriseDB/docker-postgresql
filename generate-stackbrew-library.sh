#!/usr/bin/env bash
set -eu

declare -A aliases=(
	[13]='latest'
	[9.6]='9'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( $(ls -d */ | grep -v ^src/) )
versions=( "${versions[@]%/}" )

# sort version numbers with highest first
IFS=$'\n'; versions=( $(echo "${versions[*]}" | sort -rV) ); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

cat <<-EOH
# this file is generated via https://github.com/EnterpriseDB/docker-postgresql/blob/$(fileCommit "$self")/$self

Maintainers: Marco Nenciarini <marco.nenciarini@enterprisedb.com> (@mnencia)
GitRepo: https://github.com/EnterpriseDB/docker-postgresql.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version in "${versions[@]}"; do
	commit="$(dirCommit "$version")"

	fullVersion="$(awk '/-server-/ {print $1}' "$version/Dockerfile" | cut -d- -f 3)"
	if [ "$fullVersion" = 14 ]; then
		fullVersion="$(awk '/-server-/{print $1}' 14/Dockerfile | cut -d- -f 3- | cut -d_ -f 1)"
	fi
	versionArches="x86_64"

	versionAliases=()
	while [ "$fullVersion" != "$version" -a "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=( $fullVersion )
		fullVersion="${fullVersion%[.-]*}"
	done
	versionAliases+=(
		$version
		${aliases[$version]:-}
	)

	echo
	cat <<-EOE
		Tags: $(join ', ' "${versionAliases[@]}")
		Architectures: amd64
		GitCommit: $commit
		Directory: $version
	EOE
done
