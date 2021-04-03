# PostgreSQL Container Images by EnterpriseDB

Maintenance scripts to generate Immutable Application Containers
for all PostgreSQL versions based on Red Hat Universal Base
Images (UBI) 8.

These images are customised to work with [Cloud
Native PostgreSQL operators by EDB](https://docs.enterprisedb.io/cloud-native-postgresql/)
for Kubernetes and Red Hat Openshift.

It is also possible to run them directly with Docker, for PostgreSQL evaluation and testing purposes only.

The images include:

- PostgreSQL
- Barman Cloud

PostgreSQL is distributed by the PGDG under the [PostgreSQL License](https://www.postgresql.org/about/licence/).

Barman Cloud is distributed by EnterpriseDB under the [GNU GPL 3 License](https://github.com/2ndquadrant-it/barman/blob/master/LICENSE).

Images are available via [Quay.io](https://quay.io/repository/enterprisedb/postgresql).

The Docker entry point is based on [Docker Postgres](https://github.com/docker-library/postgres)
distributed by the PostgreSQL Docker Community under MIT license.

# How to pull the image

The image can be pulled with the `docker pull` command, following the instructions you
find in the Quay.io repository.

For example you can pull the latest minor version of the latest major version of PostgreSQL
with the following command:

```console
docker pull quay.io/enterprisedb/postgresql
```

If you want to use the latest minor version of a particular major version of PostgreSQL,
for example 12, you can type:

```console
docker pull quay.io/enterprisedb/postgresql:12
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
