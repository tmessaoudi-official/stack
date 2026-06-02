#!/bin/bash

set -euo pipefail

# Capture output separately so a connection failure is distinguishable from a populated DB.
# Piping psql directly into grep masks psql's exit code: both "DB has tables" and
# "connection failed" produce no "(0 rows)" match, causing a silent skip on failure.
_psql_out=$(PGPASSWORD="${DATABASE_PASSWORD}" psql -h "${DATABASE_HOST}" -p "${DATABASE_PORT:-5432}" \
    -U "${DATABASE_USER}" -d "${DATABASE_NAME}" \
    -c "SELECT tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" \
    2>&1) || { echo "ERROR: cannot connect to PostgreSQL at ${DATABASE_HOST}:${DATABASE_PORT:-5432} — ${_psql_out}" >&2; exit 1; }

if ! printf '%s\n' "${_psql_out}" | grep -q "(0 rows)"; then
    echo "Database already populated"
else
    echo "Importing database dump ${1} to database: ${DATABASE_NAME}, server: ${DATABASE_HOST}"
    if [[ "${1}" == *\.bak ]]; then
        echo "pg_restore .bak"
        if ! PGPASSWORD="${DATABASE_PASSWORD}" pg_restore --no-owner -h "${DATABASE_HOST}" -p "${DATABASE_PORT:-5432}" -U "${DATABASE_USER}" -d "${DATABASE_NAME}" -Fc "${1}"; then
            echo "ERROR: pg_restore failed for ${1}" >&2
            exit 1
        fi
        echo "Finished"
    elif [[ "${1}" == *\.sql ]]; then
        echo "psql .sql"
        if ! PGPASSWORD="${DATABASE_PASSWORD}" psql -h "${DATABASE_HOST}" -p "${DATABASE_PORT:-5432}" -U "${DATABASE_USER}" -d "${DATABASE_NAME}" -f "${1}"; then
            echo "ERROR: psql import failed for ${1}" >&2
            exit 1
        fi
        echo "Finished"
    else
        echo "Unsupported file format"
    fi
fi
