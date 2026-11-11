#!/bin/bash

for DB in ${POSTGRES_DBS//[\"\']/}; do
    psql -U root -c "CREATE DATABASE ${DB};"
done