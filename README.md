# PostgreSQL Database Service (pg-extended)

A production-ready PostgreSQL database service with built-in connection pooling, monitoring, backup solutions, and various extensions.

> Note: default project name is `pg-extended`, you can change it by editing the `docker-compose.yml` file.
> If you wish to change the project name, make sure to update all the occurrences of the project name (`pg-extended`) in the `docker-compose.yml` file.

## Features

### Core Components

- **PostgreSQL 17.2**: Base image as starting point
- **PgBouncer**: Connection pooling to manage database connections efficiently
- **Supervisord**: Process management for enhanced control and recovery operations

### Extensions
- **TimescaleDB**: For time-series data management
- **pg_stat_statements**: For query performance monitoring and statistics
- **pg_cron**: For scheduled database operations
- **plsh**: Enables running shell scripts from PostgreSQL
- **pg_repack**: For table/index reorganization

### Other tools
- **pgBackRest**: For robust backup and recovery operations
- **PgBadger**: For log analysis
- **Discord Webhook**: For logging backups success/failure to a discord channel

### Networking & Storage

- **Network**: Isolated bridge network (`pg-extended-db-net`)
- **Volumes**:
  - `pg-extended-db-data`: For persistent database storage
  - `pg-extended-db-backups`: For backup storage


## Why Supervisor?

The database runs under Supervisor instead of directly as PID 1 for several critical reasons:

1. **Recovery Operations**: When PostgreSQL runs as PID 1, stopping it means stopping the container. With Supervisor:
   - We can stop/start PostgreSQL without container termination
   - This enables smooth backup recovery operations
   - Allows for maintenance tasks requiring database restart

2. **Process Management**:
   - Automatic restart on failure
   - Better logging and process control
   - Ability to run multiple processes if needed

## Configuration

### Required Environment Variables

Create a `.env` file based on `.env.example`:

### Optional PgAdmin

A separate docker-compose file (`docker-compose-pgadmin.yml`) is provided for PgAdmin.

You can copy the content of the file into the `docker-compose.yml` file to include it in the same stack.

Environment variables for PgAdmin are in `.env.example.pgadmin`

```bash
PGADMIN_PORT=xxxx
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=your_secure_password
```

## Usage

### Build the images

docker-compose --env-file .env -f docker-compose.yml build --progress=plain

### Starting the containers

docker-compose --env-file .env -f docker-compose.yml up -d

### Starting PgAdmin (Optional)

docker compose -f docker-compose-pgadmin.yml up -d

## Monitoring

### Logs

Logs are stored in the `pg_log` directory and are rotated daily with a weekly retention policy by default. Please refer to `custom.conf` to change this behavior.

To view the log files, run the following command:

```bash
ls -lh ${PGDATA}/pg_log
```

### PgBadger


PgBadger is installed and configured to analyze the logs.
View the doc to learn more: https://pgbadger.darold.net/

## Backup System

### Automated Backups

The system includes automated backup scheduling:
- Full backups every Sunday at 00:00
- Incremental backups Monday through Saturday at 00:00

> ### S3 Backups
> Backups to S3 can be enabled by uncommenting the S3 configuration in `pgbackrest.conf`, `docker-compose.yml` and `Dockerfile` and setting the following environment variables:
> 
> - `BACKUP_S3_ENDPOINT`
> - `BACKUP_S3_BUCKET`
> - `BACKUP_S3_REGION`
> - `BACKUP_S3_KEY`
> - `BACKUP_S3_KEY_SECRET`
> - `BACKUP_S3_FOLDER`
> 
> While testing the S3 backups, these can be slow depending on a lot of factors...

### Running Manual Backups

For a full backup:
```bash
./backup.sh full

```
or from the database:
```sql
select backup('full');
```

For an incremental backup:
```bash
./backup.sh incremental
```
or from the database:
```sql
select backup('incremental');
```
### Recovery Process

To recover from a backup:

1. Stop PostgreSQL service:
```bash
supervisorctl stop postgres;supervisorctl update
```

2. Create a safety backup of current data:
```bash
cp -r ${PGDATA} ${PGVOLUME}/pg-extended-pgdata-safety
```

3. Switch to postgres user:
```bash
su postgres
```

4. Remove postmaster.pid if needed (ensure PostgreSQL is not running):
```bash
rm -f ${PGDATA}/postmaster.pid
```

5. Start pgbackrest restore:
```bash
pgbackrest restore --stanza=${PGBACKREST_STANZA} --delta
```

6. Restart PostgreSQL:
```bash
supervisorctl start postgres; supervisorctl update
```


## Important Notes

- In `docker-compose.yml` replace the default project name with your project name
- Ensure all required environment variables are set
- The environment variables you set during the first build for the postgres database, user and password will be used to connect to the database. If you wish to create a new user and database, you can do so using SQL. Just google it, there are plenty of resources online.
- Review and adjust backup schedules as needed
- Consider security implications when exposing ports
- Monitor backup logs for successful execution
- Regularly test backup recovery process