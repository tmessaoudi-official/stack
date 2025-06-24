#!/bin/bash

if ! PGPASSWORD=${DATABASE_PASSWORD} psql -h ${DATABASE_HOST} -U ${DATABASE_USER} -d ${DATABASE_NAME} -c "SELECT tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" | grep -q "(0 rows)"; then
    echo "Database already populated"
else
    echo "Importing database dump ${1} to database: ${DATABASE_NAME}, server: ${DATABASE_HOST}"
    PGPASSWORD=${DATABASE_PASSWORD} pg_restore --no-owner -h ${DATABASE_HOST} -U ${DATABASE_USER} -d ${DATABASE_NAME} -Fc "${1}"
fi