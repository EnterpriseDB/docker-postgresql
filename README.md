# PostgreSQL Container Images by EnterpriseDB

Maintenance scripts to generate Immutable Application Containers
for all available PostgreSQL versions (11 to 15) based on:

- Red Hat Universal Base Images (UBI) 8 - default (with and without the PostGIS extension)
- Debian Buster (10) Slim base images

UBI8 based images are available for amd64, arm64, ppc64le and s390x architectures.
Debian 10 based images are available for amd64 and arm64 architectures.

Multilang images (`-multilang`) are container images enhanced with the full list of Locales. Available for all UBI based images.

These images are customised to work with [EDB Postgres for Kubernetes by EDB](https://www.enterprisedb.com/docs/postgres_for_kubernetes/latest/)
for Kubernetes and Red Hat Openshift.

It is also possible to run them directly with Docker, for PostgreSQL evaluation and testing purposes only.

The images include:

- PostgreSQL
- Barman Cloud
- PostGIS 3.1 (optional, on UBI based images only)
- PGAudit
- pgRouting (on PostGIS UBI images only)
- Postgres Failover Slots
- All language packs for glibc (optional, on UBI based images only)

PostgreSQL is distributed by the PGDG under the [PostgreSQL License](https://www.postgresql.org/about/licence/).

Barman Cloud is distributed by EnterpriseDB under the [GNU GPL 3 License](https://github.com/2ndquadrant-it/barman/blob/master/LICENSE).

PostGIS is distributed under the [GNU GPL 2 License](https://git.osgeo.org/gitea/postgis/postgis/src/branch/master/COPYING).

PGAudit is distributed under the [PostgreSQL License](https://github.com/pgaudit/pgaudit/blob/master/LICENSE).

pgRouting is distributed under the
[GNU GPL 2 License](https://github.com/pgRouting/pgrouting/blob/main/LICENSE),
with the some Boost extensions being available under
[Boost Software License](https://docs.pgrouting.org/latest/en/pgRouting-introduction.html#licensing).

Postgres Failover Slots is distributed by EnterpriseDB under the
[PostgreSQL License](https://github.com/EnterpriseDB/pg_failover_slots/blob/master/LICENSE).

The Docker entry point is based on [Docker Postgres](https://github.com/docker-library/postgres)
distributed by the PostgreSQL Docker Community under MIT license.

# Where to get them

Images are available via [GitHub Container Registry](https://github.com/EnterpriseDB/docker-postgresql/pkgs/container/postgresql)
and [Quay.io](https://quay.io/repository/enterprisedb/postgresql).

# How to pull the image

The image can be pulled with the `docker pull` command, following the instructions you
find in the GitHub Container Registy (GHCR) or Quay.io.

For example you can pull the latest minor version of the latest major version of PostgreSQL
based on RedHat UBI from GHCR with the following command:

```console
docker pull ghcr.io/enterprisedb/postgresql
```

Note: replace `ghcr.io` with `quay.io` to download from Quay.io.

If you want to use the latest minor version of a particular major version of PostgreSQL,
for example 15, on UBI you can type:

```console
docker pull ghcr.io/enterprisedb/postgresql:15
```

In order to install the latest minor version of PostgreSQL 15 on a Debian based image,
you can type:

```console
docker pull ghcr.io/enterprisedb/postgresql:15-debian
```

**IMPORTANT:** in the examples below we assume that the latest minor of the latest major version is used.

# How to use this image with Docker

## Start a PostgreSQL instance in background

```console
$ docker run -d \
   --name some-postgres \
   -e POSTGRES_PASSWORD=mysecretpassword \
   ghcr.io/enterprisedb/postgresql
```

The default `postgres` user and database are created in the entrypoint with `initdb`.

> The postgres database is a default database meant for use by users, utilities and third party applications.
>
> [postgresql.org/docs](http://www.postgresql.org/docs/current/interactive/app-initdb.html)

## Disposable environment to run SQL commands via psql

You can spin up a disposable PostgreSQL database and run queries using the
psql command line client utility with:

```console
$ docker run -it --rm \
   --network some-network \
   ghcr.io/enterprisedb/postgresql \
   psql -h some-postgres -U postgres
psql (15.1)
Type "help" for help.

postgres=# SELECT 1;
 ?column?
----------
        1
(1 row)

```

---

![Continuous Integration](https://github.com/EnterpriseDB/docker-postgresql/workflows/Continuous%20Integration/badge.svg?branch=master)
![Continuous Delivery](https://github.com/EnterpriseDB/docker-postgresql/workflows/Continuous%20Delivery/badge.svg?branch=master)
![Automatic Updates](https://github.com/EnterpriseDB/docker-postgresql/workflows/Automatic%20Updates/badge.svg?branch=master)
