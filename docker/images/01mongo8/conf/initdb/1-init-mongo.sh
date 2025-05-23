#!/bin/bash

for DB in ${MONGO_DBS//[\"\']/}; do
    mongosh --eval "db = db.getSiblingDB('${DB}'); db.createCollection('init'); db.init.insertOne({name: 'example'})"
done