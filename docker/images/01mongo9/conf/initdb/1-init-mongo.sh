#!/bin/bash

for DB in ${MONGO_DBS}; do
    if [[ ! "${DB}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "WARNING: skipping invalid DB name '${DB}'" >&2
        continue
    fi
    mongosh --eval "db = db.getSiblingDB('${DB}'); db.createCollection('init'); db.init.insertOne({name: 'example'})"
done