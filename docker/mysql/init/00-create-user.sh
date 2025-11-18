#!/bin/bash
set -e

# This script creates the MySQL user with all necessary privileges
# It runs before the SQL scripts in docker-entrypoint-initdb.d

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`siimut\`.* TO '${MYSQL_USER}'@'%';
    GRANT ALL PRIVILEGES ON \`laravel_iam\`.* TO '${MYSQL_USER}'@'%';
    GRANT ALL PRIVILEGES ON \`client_iiam\`.* TO '${MYSQL_USER}'@'%';
    FLUSH PRIVILEGES;
EOSQL

echo "MySQL user ${MYSQL_USER} created with access to all project databases"
