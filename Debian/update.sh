#!/bin/bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

defaultDebianSuite='buster-slim'
declare -A debianSuite=(
	# https://github.com/docker-library/postgres/issues/582
	[9.6]='stretch-slim'
	[10]='stretch-slim'
	[11]='stretch-slim'
)
defaultAlpineVersion='3.13'
declare -A alpineVersion=(
	#[9.6]='3.5'
)

packagesBase='http://apt.postgresql.org/pub/repos/apt/dists/'
declare -A suitePackageList=() suiteVersionPackageList=() suiteArches=()

_raw_package_list() {
	local suite="$1"; shift
	local component="$1"; shift
	local arch="$1"; shift

	curl -fsSL "$packagesBase/$suite-pgdg/$component/binary-$arch/Packages.bz2" | bunzip2
}

fetch_suite_package_list() {
	local suite="$1"; shift
	local version="$1"; shift
	local arch="$1"; shift

	# normal (GA) releases end up in the "main" component of upstream's repository
	if [ -z "${suitePackageList["$suite-$arch"]:+isset}" ]; then
		local suiteArchPackageList
		suiteArchPackageList="$(_raw_package_list "$suite" 'main' "$arch")"
		suitePackageList["$suite-$arch"]="$suiteArchPackageList"
	fi

	# ... but pre-release versions (betas, etc) end up in the "PG_MAJOR" component (so we need to check both)
	if [ -z "${suiteVersionPackageList["$suite-$version-$arch"]:+isset}" ]; then
		local versionPackageList
		versionPackageList="$(_raw_package_list "$suite" "$version" "$arch")"
		suiteVersionPackageList["$suite-$version-$arch"]="$versionPackageList"
	fi
}

awk_package_list() {
	local suite="$1"; shift
	local version="$1"; shift
	local arch="$1"; shift

	awk -F ': ' -v version="$version" "$@" <<<"${suitePackageList["$suite-$arch"]}"$'\n'"${suiteVersionPackageList["$suite-$version-$arch"]}"
}

fetch_suite_arches() {
	local suite="$1"; shift

	if [ -z "${suiteArches["$suite"]:+isset}" ]; then
		local suiteRelease
		suiteRelease="$(curl -fsSL "$packagesBase/$suite-pgdg/Release")"
		suiteArches["$suite"]="$(gawk <<<"$suiteRelease" -F ':[[:space:]]+' '$1 == "Architectures" { print $2; exit }')"
	fi
}

# record_version(versionFile, component, componentVersion)
# Parameters:
#   versionFile: the file containing the version of each component
#   component: the component to be updated
#   componentVersion: the new component version to be set
record_version() {
	local versionFile="$1"; shift
	local component="$1"; shift
	local componentVersion="$1"; shift

	jq -S --arg component "${component}" \
		--arg componentVersion "${componentVersion}" \
		'.[$component] = $componentVersion' <"${versionFile}" >>"${versionFile}.new"

	mv "${versionFile}.new" "${versionFile}"
}

for version in "${versions[@]}"; do
	tag="${debianSuite[$version]:-$defaultDebianSuite}"
	suite="${tag%%-slim}"
	majorVersion="${version%%.*}"

  versionFile="${version}/.versions.json"

	fetch_suite_package_list "$suite" "$version" 'amd64'
	fullVersion="$(
		awk_package_list "$suite" "$version" 'amd64' '
			$1 == "Package" { pkg = $2 }
			$1 == "Version" && pkg == "postgresql-" version { print $2; exit }
		'
	)"
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: missing postgresql-$version package!"
		exit 1
	fi


	fetch_suite_arches "$suite"
	versionArches=
	for arch in ${suiteArches["$suite"]}; do
		fetch_suite_package_list "$suite" "$version" "$arch"
		archVersion="$(
			awk_package_list "$suite" "$version" "$arch" '
				$1 == "Package" { pkg = $2 }
				$1 == "Version" && pkg == "postgresql-" version { print $2; exit }
			'
		)"
		if [ "$archVersion" = "$fullVersion" ]; then
			[ -z "$versionArches" ] || versionArches+=' | '
			versionArches+="$arch"
		fi
	done

	echo "$version: $fullVersion ($versionArches)"

	cp docker-entrypoint.sh "$version/"
  cp initdb-postgis.sh "$version/"
  cp update-postgis.sh "$version/"

	sed -e 's/%%PG_MAJOR%%/'"$version"'/g;' \
		-e 's/%%PG_VERSION%%/'"$fullVersion"'/g' \
		-e 's/%%DEBIAN_TAG%%/'"$tag"'/g' \
		-e 's/%%DEBIAN_SUITE%%/'"$suite"'/g' \
		-e 's/%%ARCH_LIST%%/'"$versionArches"'/g' \
		Dockerfile-debian.template \
		> "$version/Dockerfile"

	sed -e 's/%%PG_MAJOR%%/'"$version"'/g;' \
		-e 's/%%PG_VERSION%%/'"$fullVersion"'/g' \
		-e 's/%%DEBIAN_TAG%%/'"$tag"'/g' \
		-e 's/%%DEBIAN_SUITE%%/'"$suite"'/g' \
		-e 's/%%ARCH_LIST%%/'"$versionArches"'/g' \
    -e 's/%%POSTGIS_MAJOR%%/"3"/g' \
		Dockerfile-postgis.template \
		> "$version/Dockerfile.postgis"

	if [ "$majorVersion" = '9' ]; then
		sed -i -e 's/WALDIR/XLOGDIR/g' \
			-e 's/waldir/xlogdir/g' \
			"$version/docker-entrypoint.sh"
		# ICU support was introduced in PostgreSQL 10 (https://www.postgresql.org/docs/10/static/release-10.html#id-1.11.6.9.5.13)
		sed -i -e '/icu/d' "$version/Dockerfile"
	else
		# postgresql-contrib-10 package does not exist, but is provided by postgresql-10
		# Packages.gz:
		# Package: postgresql-10
		# Provides: postgresql-contrib-10
		  sed -i -e '/postgresql-contrib-/d' "$version/Dockerfile"
      sed -i -e '/postgresql-contrib-/d' "$version/Dockerfile.postgis"
	fi

	if [ "$majorVersion" != '13' ]; then
		sed -i -e '/DEBIAN_FRONTEND/d' "$version/Dockerfile"
	fi

  postgresqlVersion=$fullVersion

  if [ -f "${versionFile}" ]; then
		oldPostgresqlVersion=$(jq -r '.POSTGRES_VERSION' "${versionFile}")
		oldImageReleaseVersion=$(jq -r '.IMAGE_RELEASE_VERSION' "${versionFile}")
	else
		imageReleaseVersion=1

		echo "{}" > "${versionFile}"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" "${imageReleaseVersion}"

		exit 1
	fi

	newRelease="false"

	# Detect an update of PostgreSQL
	if [ "$oldPostgresqlVersion" != "$postgresqlVersion" ]; then
		echo "PostgreSQL changed from $oldPostgresqlVersion to $postgresqlVersion"
		record_version "${versionFile}" "POSTGRES_VERSION" "${postgresqlVersion}"
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" 1
	elif [ "$newRelease" = "true" ]; then
		imageReleaseVersion=$((oldImageReleaseVersion + 1))
		record_version "${versionFile}" "IMAGE_RELEASE_VERSION" $imageReleaseVersion
	fi


	# TODO figure out what to do with odd version numbers here, like release candidates
	srcVersion="${fullVersion%%-*}"
	# change "10~beta1" to "10beta1" for ftp urls
	tilde='~'
	srcVersion="${srcVersion//$tilde/}"
	srcSha256="$(curl -fsSL "https://ftp.postgresql.org/pub/source/v${srcVersion}/postgresql-${srcVersion}.tar.bz2.sha256" | cut -d' ' -f1)"
	for variant in alpine; do
		if [ ! -d "$version/$variant" ]; then
			continue
		fi

		cp docker-entrypoint.sh "$version/$variant/"
		sed -i 's/gosu/su-exec/g' "$version/$variant/docker-entrypoint.sh"
		sed -e 's/%%PG_MAJOR%%/'"$version"'/g' \
			-e 's/%%PG_VERSION%%/'"$srcVersion"'/g' \
			-e 's/%%PG_SHA256%%/'"$srcSha256"'/g' \
			-e 's/%%ALPINE-VERSION%%/'"${alpineVersion[$version]:-$defaultAlpineVersion}"'/g' \
			"Dockerfile-$variant.template" \
			> "$version/$variant/Dockerfile"
		if [ "$majorVersion" = '9' ]; then
			sed -i -e 's/WALDIR/XLOGDIR/g' \
				-e 's/waldir/xlogdir/g' \
				"$version/$variant/docker-entrypoint.sh"
			# ICU support was introduced in PostgreSQL 10 (https://www.postgresql.org/docs/10/static/release-10.html#id-1.11.6.9.5.13)
			sed -i -e '/icu/d' "$version/$variant/Dockerfile"
		fi

		if [ "$majorVersion" -gt 11 ]; then
			sed -i '/backwards compat/d' "$version/$variant/Dockerfile"
		fi
		if [ "$majorVersion" -lt 11 ]; then
			# JIT / LLVM is only supported in PostgreSQL 11+ (https://github.com/docker-library/postgres/issues/475)
			sed -i '/llvm/d' "$version/$variant/Dockerfile"
		fi
	done
done
