#!/bin/bash

set -euo pipefail

_dest="${1}"
_tmp="${_dest}.part.$$"

if ! PGPASSWORD="$DATABASE_PASSWORD" pg_dump --no-owner -h "$DATABASE_HOST" -p "${DATABASE_PORT:-5432}" -U "$DATABASE_USER" -w -Fc "$DATABASE_NAME" >"${_tmp}"; then
  echo "ERROR: pg_dump failed" >&2
  rm -f "${_tmp}"
  exit 1
fi
mv "${_tmp}" "${_dest}"
echo "Finished"
