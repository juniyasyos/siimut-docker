-- Create databases for all projects
CREATE DATABASE IF NOT EXISTS `siimut` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `laravel_iam` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `client_iiam` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant privileges to the application user
-- The user will be created from MYSQL_USER environment variable
GRANT ALL PRIVILEGES ON `siimut`.* TO '${MYSQL_USER}'@'%';
GRANT ALL PRIVILEGES ON `laravel_iam`.* TO '${MYSQL_USER}'@'%';
GRANT ALL PRIVILEGES ON `client_iiam`.* TO '${MYSQL_USER}'@'%';

FLUSH PRIVILEGES;
