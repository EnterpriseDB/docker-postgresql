# vim:set ft=dockerfile:
ARG BASE_REGISTRY=registry1.dso.mil
ARG BASE_IMAGE=redhat/ubi/ubi8
ARG BASE_TAG=8.4
FROM ${BASE_REGISTRY}/${BASE_IMAGE}:${BASE_TAG}

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG C.UTF-8

COPY scripts/* /usr/local/bin/
RUN chmod 755 /usr/local/bin/*

ARG PG_USER_ID="26"
ARG PG_USER_NAME="postgres"

ARG PG_GROUP_ID="26"
ARG PG_GROUP_NAME="postgres"

ARG PG_VERSION=10

COPY ./RPM-GPG-KEY-PGDG-10 \
	./postgresql10-10.21-1PGDG.rhel8.x86_64.rpm \
	./postgresql10-contrib-10.21-1PGDG.rhel8.x86_64.rpm \
	./postgresql10-server-10.21-1PGDG.rhel8.x86_64.rpm \
	./postgresql10-libs-10.21-1PGDG.rhel8.x86_64.rpm \
	./pgaudit12_10-1.2.4-1.rhel8.x86_64.rpm \
	./requirements.txt \
	./*.whl \
	./*.tar.gz \
	/tmp/

# Install from local copies of RPMs
RUN dnf update -y --nodocs && \
    dnf clean all && \
	rpm --import /tmp/RPM-GPG-KEY-PGDG-10 && \
	dnf -y reinstall \
	tar \
	glibc-common  && \
	dnf -y install --nodocs \
	bind-utils \
	cargo \
	gcc \ 
	gettext \
	glibc-langpack-en \
	glibc-locale-source \
	hostname \
	libffi-devel \
	libpq-devel \
	nss_wrapper \
	openssl-devel \
	python38-cffi \
	python38-cryptography \
	python38-devel\ 
	python38-pip \
	python38-pip-wheel \
	python38-psycopg2 \
	python38-setuptools \
	redhat-lsb-core \
	redhat-rpm-config \
	rsync \
	/tmp/postgresql10-10.21-1PGDG.rhel8.x86_64.rpm \
	/tmp/postgresql10-contrib-10.21-1PGDG.rhel8.x86_64.rpm \
	/tmp/postgresql10-server-10.21-1PGDG.rhel8.x86_64.rpm \
	/tmp/postgresql10-libs-10.21-1PGDG.rhel8.x86_64.rpm \
	/tmp/pgaudit12_10-1.2.4-1.rhel8.x86_64.rpm \
	&& rm -rf /var/cache/dnf

# Install barman-cloud
ENV CRYPTOGRAPHY_DONT_BUILD_RUST 1 
ENV CARGO_NET_OFFLINE true
RUN python3 -m pip install --no-index --find-links=/tmp --upgrade /tmp/pip-21.3.1-py3-none-any.whl
RUN pip3 install --no-index --find-links=/tmp -r /tmp/requirements.txt
RUN rm -rf /tmp/*.{rpm,whl} && \
	dnf -y remove python38-devel openssl-devel gcc cargo libffi-devel redhat-rpm-config

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
	sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/pgsql-10/share/postgresql.conf.sample; \
	grep -F "listen_addresses = '*'" /usr/pgsql-10/share/postgresql.conf.sample

# prepare the environment and make sure postgres user has the correct UID
RUN set -xeu ; \
	localedef -f UTF-8 -i en_US en_US.UTF-8 ; \
	test "$(id postgres)" = "uid=26(postgres) gid=26(postgres) groups=26(postgres)" ; \
	mkdir -p /var/run/postgresql ; \
	chown postgres:postgres /var/run/postgresql ; \
	chmod 0755 /var/run/postgresql

ENV PATH $PATH:/usr/pgsql-10/bin

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

ENV PGDATA /var/lib/postgresql/data/pgdata
# this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA"
VOLUME /var/lib/postgresql/data

RUN mkdir /docker-entrypoint-initdb.d && \
    chown postgres:postgres /docker-entrypoint-initdb.d && \
    chmod 755 /docker-entrypoint-initdb.d && \
    mkdir -p "$PGDATA" && \
    chown -R postgres:postgres "$PGDATA" && \
    chmod 775 "$PGDATA" && \
    sed -ri s/"#?(listen_addresses)\s*=\s*\S+.*"/"listen_addresses = '*'"/ /usr/pgsql-10/share/postgresql.conf.sample && \
    grep -F "listen_addresses = '*'" /usr/pgsql-10/share/postgresql.conf.sample

# DoD 2.3 - remove setuid/setgid from any binary that not strictly requires it, and before doing that list them on the stdout
RUN find / -not -path "/proc/*" -perm /6000 -type f -exec ls -ld {} \; -exec chmod a-s {} \; || true

HEALTHCHECK --interval=5s --timeout=3s CMD /usr/pgsql-10/bin/pg_isready -U postgres
USER ${PG_USER_ID}
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# We set the default STOPSIGNAL to SIGINT, which corresponds to what PostgreSQL
# calls "Fast Shutdown mode" wherein new connections are disallowed and any
# in-progress transactions are aborted, allowing PostgreSQL to stop cleanly and
# flush tables to disk, which is the best compromise available to avoid data
# corruption.
#
# Users who know their applications do not keep open long-lived idle connections
# may way to use a value of SIGTERM instead, which corresponds to "Smart
# Shutdown mode" in which any existing sessions are allowed to finish and the
# server stops when all sessions are terminated.
#
# See https://www.postgresql.org/docs/10/server-shutdown.html for more details
# about available PostgreSQL server shutdown signals.
#
# See also https://www.postgresql.org/docs/10/server-start.html for further
# justification of this as the default value, namely that the example (and
# shipped) systemd service files use the "Fast Shutdown mode" for service
# termination.
#
STOPSIGNAL SIGINT
#
# An additional setting that is recommended for all users regardless of this
# value is the runtime "--stop-timeout" (or your orchestrator/runtime's
# equivalent) for controlling how long to wait between sending the defined
# STOPSIGNAL and sending SIGKILL (which is likely to cause data corruption).
#
# The default in most runtimes (such as Docker) is 10 seconds, and the
# documentation at https://www.postgresql.org/docs/10/server-start.html notes
# that even 90 seconds may not be long enough in many instances.

EXPOSE 5432
CMD ["postgres"]
