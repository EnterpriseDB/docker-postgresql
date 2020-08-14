# vim:set ft=dockerfile:
FROM registry.access.redhat.com/ubi8/ubi:8.2-343

LABEL name="PostgreSQL Container Images" \
      vendor="2ndQuadrant" \
      url="https://www.2ndquadrant.com/" \
      version="9.5.23-1PGDG.rhel8" \
      release="1" \
      summary="PostgreSQL Container images." \
      description="This Docker image contains PostgreSQL and Barman Cloud  \
                   based on RedHat Universal Base Images (UBI) 8."

COPY root/ /

RUN set -xe ; \
	yum -y reinstall glibc-common ; \
	yum -y install hostname rsync tar gettext bind-utils nss_wrapper glibc-locale-source glibc-langpack-en ; \
	yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm ; \
	yum -y --setopt=tsflags=nodocs install \
		postgresql95-9.5.23-1PGDG.rhel8 \
		postgresql95-contrib-9.5.23-1PGDG.rhel8 \
		postgresql95-server-9.5.23-1PGDG.rhel8 \
		postgresql95-libs-9.5.23-1PGDG.rhel8 ; \
	yum -y clean all --enablerepo='*'

# Install barman-cloud
RUN set -xe ; \
	yum -y install python38-pip python38-psycopg2 ; \
	pip3.8 install barman[cloud]=="2.11" ; \
	yum -y clean all --enablerepo='*'

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
	sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/pgsql-9.5/share/postgresql.conf.sample; \
	grep -F "listen_addresses = '*'" /usr/pgsql-9.5/share/postgresql.conf.sample

# prepare the environment and make sure postgres user has the correct UID
RUN set -xeu ; \
	localedef -f UTF-8 -i en_US en_US.UTF-8 ; \
	test "$(id postgres)" = "uid=26(postgres) gid=26(postgres) groups=26(postgres)" ; \
	mkdir -p /var/run/postgresql ; \
	chown postgres:postgres /var/run/postgresql ; \
	chmod 0755 /var/run/postgresql

ENV PATH $PATH:/usr/pgsql-9.5/bin

USER 26

EXPOSE 5432
