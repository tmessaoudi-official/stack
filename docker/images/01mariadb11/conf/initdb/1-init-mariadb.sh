#!/bin/bash

# Allow root access from any host
mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;"
# Allow root access from any host
mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION;"
mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;"

for DB in ${MARIADB_DBS//[\"\']/}; do
    mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS ${DB};"
done