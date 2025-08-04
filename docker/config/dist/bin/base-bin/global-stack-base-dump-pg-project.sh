#!/bin/bash

PGPASSWORD=$DATABASE_PASSWORD pg_dump --no-owner -h $DATABASE_HOST -p ${DATABASE_PORT:-5432} -U $DATABASE_USER -w -Fc $DATABASE_NAME > "${1}"
echo "Finished"