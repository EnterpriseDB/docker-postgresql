# PostgreSQL Container Images by EnterpriseDB

Maintenance scripts to generate Immutable Application Containers
for all PostgreSQL versions based on:

- Red Hat Universal Base Images (UBI) 8 - default
- Debian Buster (10) Slim base images, with and without the PostGIS extension

UBI8 based images of versions 11,12 and 13 are available for amd64, ppc64le and s390x architectures.

These images are customised to work with [Cloud
Native PostgreSQL operators by EDB](https://docs.enterprisedb.io/cloud-native-postgresql/)
for Kubernetes and Red Hat Openshift.

It is also possible to run them directly with Docker, for PostgreSQL evaluation and testing purposes only.

The images include:

- PostgreSQL
- Barman Cloud
- PostGIS 3.1 (optional, on Debian based images only)
- PGAudit

PostgreSQL is distributed by the PGDG under the [PostgreSQL License](https://www.postgresql.org/about/licence/).

Barman Cloud is distributed by EnterpriseDB under the [GNU GPL 3 License](https://github.com/2ndquadrant-it/barman/blob/master/LICENSE).

PostGIS is distributed under the [GNU GPL 2 License](https://git.osgeo.org/gitea/postgis/postgis/src/branch/master/COPYING).

PGAudit is distributed under the [PostgreSQL License](https://github.com/pgaudit/pgaudit/blob/master/LICENSE).

Images are available via [Quay.io](https://quay.io/repository/enterprisedb/postgresql).

The Docker entry point is based on [Docker Postgres](https://github.com/docker-library/postgres)
distributed by the PostgreSQL Docker Community under MIT license.

# How to pull the image

The image can be pulled with the `docker pull` command, following the instructions you
find in the Quay.io repository.

For example you can pull the latest minor version of the latest major version of PostgreSQL
based on RedHat UBI with the following command:

```console
docker pull quay.io/enterprisedb/postgresql
```

If you want to use the latest minor version of a particular major version of PostgreSQL,
for example 12, on UBI you can type:

```console
docker pull quay.io/enterprisedb/postgresql:12
```

In order to install the latest minor version of PostgreSQL 12 on a Debian based image,
you can type:

```console
docker pull quay.io/enterprisedb/postgresql:12-debian
```

**IMPORTANT:** in the examples below we assume that the latest minor of the latest major version is used.

# How to use this image with Docker

## Start a PostgreSQL instance in background

```console
$ docker run -d \
   --name some-postgres \
   -e POSTGRES_PASSWORD=mysecretpassword \
   quay.io/enterprisedb/postgresql
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
   quay.io/enterprisedb/postgresql \
   psql -h some-postgres -U postgres
psql (13.1)
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
