FROM postgres:17.2

####################################################
# Environment variables
# When changing, make sure you crtl+d to change all
# occurences as some commands can't use variables.
# Also, make sure to update all scripts for any 
# occurences of the variables.
####################################################

# use bash as default shell
RUN ln -sf /bin/bash /bin/sh

# Discord webhook
ARG DISCORD_WEBHOOK
ENV DISCORD_WEBHOOK=${DISCORD_WEBHOOK:-""}

# Enable cron backup
ARG CRON_BACKUP_ENABLED
ENV CRON_BACKUP_ENABLED=${CRON_BACKUP_ENABLED:-"true"}

# Database
ARG POSTGRES_DB
ARG POSTGRES_USER
ENV POSTGRES_DB=${POSTGRES_DB}
ENV POSTGRES_USER=${POSTGRES_USER}

# Volumes 
ENV PGVOLUME=/var/lib/postgresql/data
ENV PGDATA=${PGVOLUME}/${POSTGRES_USER}-pgdata

# Postgresql configuration and other directories
ENV POSTGRES_CUSTOM_CONF=${PGVOLUME}/custom.conf
ENV TIMESCALE_CUSTOM_CONF=${PGVOLUME}/timescale-custom.conf
ENV POSTGRES_CONF=${PGDATA}/postgresql.conf
ENV PG_LOG_DIR=${PGDATA}/pg_log

# Directories
ENV LOCAL_BIN=/usr/local/bin
ENV LOCAL_SHARE=/usr/share/postgresql/17
ENV SCRIPTS_DIR=${LOCAL_BIN}/scripts

# Backups configuration
ENV PGBACKREST_STANZA=${POSTGRES_USER}
ENV PGBACKREST_CONFIG=/etc/pgbackrest/pgbackrest.conf
ENV PGBACKREST_LOG_PATH=/var/log/pgbackrest
ENV PGBACKREST_REPO1_PATH=/var/lib/pgbackrest
ENV PGBACKREST_PG1_PATH=${PGDATA}
ENV PGBACKREST_PG1_USER=${POSTGRES_USER}
ENV PGBACKREST_PG1_DATABASE=${POSTGRES_DB}
ARG BACKUP_CIPHER_PASS
ENV PGBACKREST_REPO1_CIPHER_PASS=${BACKUP_CIPHER_PASS}
ENV PGBACKREST_SPOOL_PATH=/var/spool/pgbackrest

# Backups S3 configuration - Uncomment to enable S3 backups
# ARG BACKUP_S3_ENDPOINT
# ENV PGBACKREST_REPO1_S3_ENDPOINT=${BACKUP_S3_ENDPOINT}
# ARG BACKUP_S3_BUCKET
# ENV PGBACKREST_REPO1_S3_BUCKET=${BACKUP_S3_BUCKET}
# ARG BACKUP_S3_REGION
# ENV PGBACKREST_REPO1_S3_REGION=${BACKUP_S3_REGION}
# ARG BACKUP_S3_KEY
# ENV PGBACKREST_REPO1_S3_KEY=${BACKUP_S3_KEY}
# ARG BACKUP_S3_KEY_SECRET
# ENV PGBACKREST_REPO1_S3_KEY_SECRET=${BACKUP_S3_KEY_SECRET}
# ARG BACKUP_S3_FOLDER
# ENV PGBACKREST_REPO1_PATH=${BACKUP_S3_FOLDER:-"/backup"}

# supervisord
ENV SUPERVISORD_CONF=/etc/supervisor/conf.d/supervisord.conf

# fail if any of the args are not set
RUN echo "Verifying passed arguments..." && \
    if \
      [ -z "${POSTGRES_DB}" ] || \
      [ -z "${POSTGRES_USER}" ] || \
      [ -z "${BACKUP_CIPHER_PASS}" ]; \
    then \
      echo "Error: Required environment variables are not set."; \
      exit 1; \
    fi;

####################################################
# Install base tools and build dependencies
####################################################

RUN apt-get update && apt-get install -y \
    vim \
    git \
    gcc \
    make \
    cmake \
    clang \
    llvm \
    curl \
    jq \
    supervisor \
    pgbadger \
    perl \
    libpq-dev \
    postgresql-common \
    postgresql-server-dev-17 \
    dos2unix \
    zlib1g-dev \
    gawk \
    pgbackrest \
    postgresql-17-cron \
    golang \
    libzstd-dev \
    liblz4-dev \
    libreadline-dev \
    && rm -rf /var/lib/apt/lists/*

####################################################
# Install TimescaleDB and timescaledb-tune
####################################################

RUN git clone https://github.com/timescale/timescaledb.git /tmp/timescaledb \
    && cd /tmp/timescaledb \
    && git checkout 2.18.0 \
    && ./bootstrap -DREGRESS=OFF \
    && cd build \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/timescaledb

# Install timescaledb-tune
ENV GOPATH=/root/go
ENV PATH=$PATH:$GOPATH/bin
RUN go install github.com/timescale/timescaledb-tune/cmd/timescaledb-tune@main \
    && touch ${TIMESCALE_CUSTOM_CONF} \
    && timescaledb-tune --quiet --yes --conf-path="$TIMESCALE_CUSTOM_CONF"

####################################################
# Install plsh from source
####################################################

RUN git clone https://github.com/petere/plsh.git /tmp/plsh \
    && cd /tmp/plsh \
    && make \
    && make install \
    && rm -rf /tmp/plsh

####################################################
# Install pg_repack from source
####################################################

RUN git clone https://github.com/reorg/pg_repack.git /tmp/pg_repack \
    && cd /tmp/pg_repack \
    && make \
    && make install \
    && rm -rf /tmp/pg_repack

####################################################
# Install and configure supervisord
####################################################
COPY conf/supervisord.conf ${SUPERVISORD_CONF}
RUN chmod 755 ${SUPERVISORD_CONF}

####################################################
# Configure pgbackrest
####################################################

COPY conf/pgbackrest.conf ${PGBACKREST_CONFIG}
RUN mkdir -p ${PGBACKREST_REPO1_PATH} \
    && chmod 750 ${PGBACKREST_REPO1_PATH} \
    && chown -R postgres:postgres ${PGBACKREST_REPO1_PATH} \
    && mkdir -p ${PGBACKREST_LOG_PATH} \
    && chmod 750 ${PGBACKREST_LOG_PATH} \
    && chown -R postgres:postgres ${PGBACKREST_LOG_PATH} \
    && chmod 755 ${PGBACKREST_CONFIG} \
    && mkdir -p ${PGBACKREST_SPOOL_PATH} \
    && chmod 750 ${PGBACKREST_SPOOL_PATH} \
    && chown -R postgres:postgres ${PGBACKREST_SPOOL_PATH}

####################################################
# Add custom configuration to postgresql.conf
####################################################

# Copy custom configuration
COPY conf/custom.conf ${POSTGRES_CUSTOM_CONF}
RUN chmod 755 ${POSTGRES_CUSTOM_CONF}

# Set permissions for PostgreSQL extensions directory
RUN chmod -R 755 ${LOCAL_SHARE}/extension

####################################################
# Add all init-db .sh and .sql scripts
####################################################

COPY init-db /tmp/init-db
RUN cp -a /tmp/init-db/. /docker-entrypoint-initdb.d/ && \
    rm -rf /tmp/init-db && \
    chmod -R +x /docker-entrypoint-initdb.d && \
    find /docker-entrypoint-initdb.d -type f -name "*.sh" -exec dos2unix {} +

####################################################
# Add all other custom scripts
####################################################

COPY scripts /tmp/scripts
RUN cp -a /tmp/scripts/. ${SCRIPTS_DIR}/ && \
    rm -rf /tmp/scripts && \
    chmod -R +x ${SCRIPTS_DIR}/ && \
    find ${SCRIPTS_DIR} -type f -name "*.sh" -exec dos2unix {} +

####################################################
# Run config change environment script
####################################################

RUN ${SCRIPTS_DIR}/conf-change-env.sh

####################################################
# Override the default entrypoint to include custom setup
# and run postgres
####################################################
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

