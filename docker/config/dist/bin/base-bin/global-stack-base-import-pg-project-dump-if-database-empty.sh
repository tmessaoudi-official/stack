#!/bin/bash

if ! PGPASSWORD=${DATABASE_PASSWORD} psql -h ${DATABASE_HOST} -U ${DATABASE_USER} -d ${DATABASE_NAME} -c "SELECT tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" | grep -q "(0 rows)"; then
    echo "Database already populated"
else
    echo "Importing database dump ${1} to database: ${DATABASE_NAME}, server: ${DATABASE_HOST}"
    if [[ "${1}" == *\.bak ]]; then
        echo "pg_restore .bak"
        PGPASSWORD=${DATABASE_PASSWORD} pg_restore --no-owner -h ${DATABASE_HOST} -p ${DATABASE_PORT:-5432} -U ${DATABASE_USER} -d ${DATABASE_NAME} -Fc "${1}"
        echo "Finished"
    elif [[ "${1}" == *\.sql ]]; then
        echo "psql .sql"
        PGPASSWORD=${DATABASE_PASSWORD} psql -h ${DATABASE_HOST} -p ${DATABASE_PORT:-5432} -U ${DATABASE_USER} -d ${DATABASE_NAME} -f "${1}"
        echo "Finished"
    else
        echo "Unsupported file format"
    fi
fi