# vim:set ft=dockerfile:
FROM quay.io/enterprisedb/edb-ubi:8.6-855

# Do not split the description, otherwise we will see a blank space in the labels
LABEL name="PostgreSQL Container Images" \
      vendor="EnterpriseDB" \
      url="https://www.enterprisedb.com/" \
      version="12.11-1PGDG.rhel8" \
      release="4" \
      summary="PostgreSQL Container images." \
      description="This Docker image contains PostgreSQL and Barman Cloud based on RedHat Universal Base Images (UBI) 8."

COPY root/ /

ARG TARGETARCH
RUN --mount=type=secret,id=cs_script,target=/run/secrets/cs_script.sh \
	set -xe ; \
	bash /run/secrets/cs_script.sh ; \
	yum -y reinstall glibc-common ; \
	yum -y install hostname rsync tar gettext bind-utils nss_wrapper glibc-locale-source glibc-langpack-en ; \
	if [ "$TARGETARCH" == 'amd64' ]; then \
		yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm ; \
	fi ; \
	yum -y --setopt=tsflags=nodocs install \
		postgresql12-12.11-1PGDG.rhel8 \
		postgresql12-contrib-12.11-1PGDG.rhel8 \
		postgresql12-server-12.11-1PGDG.rhel8 \
		postgresql12-libs-12.11-1PGDG.rhel8 \
		pgaudit14_12 \
	; \
	rm -fr /etc/yum.repos.d/enterprisedb-edb.repo ; \
	rm -fr /tmp/* ; \
	yum -y clean all --enablerepo='*'

# Install barman-cloud
RUN set -xe ; \
	yum -y install python38-pip python38-psycopg2 ; \
	pip3.8 install --upgrade pip ; \
	pip3.8 install -r requirements.txt ; \
	yum -y clean all --enablerepo='*'

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
	sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/pgsql-12/share/postgresql.conf.sample; \
	grep -F "listen_addresses = '*'" /usr/pgsql-12/share/postgresql.conf.sample

# prepare the environment and make sure postgres user has the correct UID
RUN set -xeu ; \
	localedef -f UTF-8 -i en_US en_US.UTF-8 ; \
	test "$(id postgres)" = "uid=26(postgres) gid=26(postgres) groups=26(postgres)" ; \
	mkdir -p /var/run/postgresql ; \
	chown postgres:postgres /var/run/postgresql ; \
	chmod 0755 /var/run/postgresql

ENV PATH $PATH:/usr/pgsql-12/bin

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

ENV PGDATA /var/lib/postgresql/data/pgdata
# this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA"
VOLUME /var/lib/postgresql/data

RUN mkdir /docker-entrypoint-initdb.d

# DoD 2.3 - remove setuid/setgid from any binary that not strictly requires it, and before doing that list them on the stdout
RUN find / -not -path "/proc/*" -perm /6000 -type f -exec ls -ld {} \; -exec chmod a-s {} \; || true

USER 26

ENTRYPOINT ["docker-entrypoint.sh"]

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
# See https://www.postgresql.org/docs/12/server-shutdown.html for more details
# about available PostgreSQL server shutdown signals.
#
# See also https://www.postgresql.org/docs/12/server-start.html for further
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
# documentation at https://www.postgresql.org/docs/12/server-start.html notes
# that even 90 seconds may not be long enough in many instances.

EXPOSE 5432
CMD ["postgres"]
