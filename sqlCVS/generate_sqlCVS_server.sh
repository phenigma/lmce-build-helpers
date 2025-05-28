#!/bin/bash


################ Note: for some reason the local sqlCVS servers connect to 'dcerouter' rather than 'localhost'
################ Need to add to /etc/hosts in the container "127.0.0.1       dcerouter"

basedir=${basedir:-builders}
container_name="sqlcvs-server"
container_dir="$HOME/$basedir/$container_name"

mkdir -p "$container_dir"/{data,logs,www,lib,bin,scripts}

# Copy required files from script dir to container_dir
cp sqlCVS-dbdump2025.tar.gz sqlcvs-server-1.0.deb reset.sh "$container_dir/"

cat > "$container_dir/Dockerfile" <<EOF
FROM ubuntu:14.04

ENV DEBIAN_FRONTEND=noninteractive

# Set APT proxy
RUN echo 'Acquire::http::Proxy "http://192.168.2.60:3142";' > /etc/apt/apt.conf.d/02proxy

# Install packages
RUN apt update && \
    apt install -y nano apache2 php5 php5-mysql php5-gd libapache2-mod-php5 libapache2-mod-auth-mysql mysql-server screen git

# Adminer
RUN ln -s /usr/share/adminer/adminer /var/www/html/adminer/

# Clone sqlCVSweb
RUN git clone https://github.com/linuxmce/sqlCVSweb.git /var/www/html/sqlCVS

# Ensure /usr/pluto directories exist
RUN mkdir -p /usr/pluto/bin /usr/pluto/lib

# Install application package
COPY sqlCVS-dbdump2025.tar.gz sqlcvs-server-1.0.deb /tmp/
RUN mkdir -p /tmp/sqlCVS-dbdump2025 \
    && tar --strip=1 -xzf /tmp/sqlCVS-dbdump2025.tar.gz -C /tmp/sqlCVS-dbdump2025 \
    && dpkg -i /tmp/sqlcvs-server-1.0.deb || apt-get install -f -y

# Optionally apply MySQL config
# RUN cp /usr/pluto/bin/90-server_sqlCVS.cnf /etc/mysql/mysql.conf.d/

# Start script
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
EOF

# start.sh script
cat > "$container_dir/start.sh" <<'EOS'
#!/bin/bash

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [startup] $1"
}

exec &> >(tee -a /var/log/startup.log)
set +e
trap 'log "Startup script exited with code $?"' EXIT

echo "========== Container Startup at $(date '+%Y-%m-%d %H:%M:%S') =========="
set -e

log "Ensuring MySQL log, run, and data directories exist"
mkdir -p /var/log/mysql /var/run/mysqld /var/lib/mysql
chown -R mysql:mysql /var/log/mysql /var/run/mysqld /var/lib/mysql

log "Checking for existing MySQL database"
initialized=false
if [ ! -d /var/lib/mysql/mysql ]; then
  log "Initializing MySQL data directory..."
  mysql_install_db --user=mysql --ldata=/var/lib/mysql
#  mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql || echo "MySQL initialization failed but continuing for container access"
  initialized=true
fi

sleep 2
rm -f /var/run/mysqld/*

log "Starting MySQL safely in background"
mysqld_safe --socket=/var/run/mysqld/mysqld.sock &

log "Waiting for MySQL to become available"
until mysqladmin --socket=/var/run/mysqld/mysqld.sock ping --silent; do
  log "Waiting for MySQL..."
  sleep 2
done

if [ "$initialized" = true ]; then
  log "Securing root user to restrict access to localhost"
  mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY ''; FLUSH PRIVILEGES;" || :
  mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD(''); FLUSH PRIVILEGES;" || :

  log "Importing SQL dump files"
  for sqlfile in /tmp/sqlCVS-dbdump2025/*.sql; do
    log "Importing database from: $sqlfile"
    dbname="$(basename "$sqlfile" .sql)"
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS $dbname; USE $dbname; SOURCE $sqlfile;" || :
  done

  log "Creating MySQL user 'websqlcvs' with remote access"
  mysql -e "CREATE USER 'websqlcvs'@'localhost' IDENTIFIED BY 'lmc3R0ckz';" || :
  log "Granting privileges on all pluto_* databases to user 'websqlcvs'"
  mysql -e "GRANT ALL PRIVILEGES ON pluto_%.* TO 'websqlcvs'@'localhost';" || :
  log "Granting privileges on MasterUsers database to user 'websqlcvs'"
  mysql -e "GRANT ALL PRIVILEGES ON MasterUsers.* TO 'websqlcvs'@'localhost';" || :
  log "Granting privileges on main_sqlcvs_utf8 database to user 'websqlcvs'"
  mysql -e "GRANT ALL PRIVILEGES ON main_sqlcvs_utf8.* TO 'websqlcvs'@'localhost';" || :
  log "Applying privilege changes by flushing privileges"
  mysql -e "FLUSH PRIVILEGES;"

## Need to setup the builder user for mysqldumps
#CREATE USER 'builder'@'%' IDENTIFIED BY '';
#update user set plugin="mysql_native_password" where User="builder";
#GRANT SELECT, LOCK TABLES ON main_sqlcvs_utf8.* TO 'builder'@'%';
#GRANT SELECT, LOCK TABLES ON main_sqlcvs.* TO 'builder'@'%';
#GRANT SELECT, LOCK TABLES ON myth_sqlcvs.* TO 'builder'@'%';

#GRANT SELECT, LOCK TABLES ON pluto_main.* TO 'builder'@'%';
#GRANT SELECT, LOCK TABLES ON pluto_media.* TO 'builder'@'%';
#GRANT SELECT, LOCK TABLES ON pluto_telecom.* TO 'builder'@'%';
#GRANT SELECT, LOCK TABLES ON pluto_security.* TO 'builder'@'%';



  log "MySQL user setup complete. Remote access enabled."
fi

log "Ensuring Apache log directory exists"
mkdir -p /var/log/apache2
chown -R www-data:www-data /var/log/apache2

log "Starting Apache"
service apache2 start

log "Launching sqlCVS applications"
# Uncomment below lines to launch sqlCVS listeners
/usr/pluto/bin/sqlCVS-server.sh
#/usr/pluto/bin/sqlCVS -D main_sqlcvs_utf8 -u root -R 3999 -h localhost listen
/usr/pluto/bin/sqlCVS-server-media.sh
#/usr/pluto/bin/sqlCVS -D pluto_media -u root -R 4999 -h localhost listen
#/usr/pluto/bin/sqlCVS-server-game.sh
#/usr/pluto/bin/sqlCVS -D lmce_game -u root -R 5999 -h localhost listen
/usr/pluto/bin/sqlCVS-server-security.sh
#/usr/pluto/bin/sqlCVS -D pluto_security -u root -R 6999 -h localhost listen
/usr/pluto/bin/sqlCVS-server-telecom.sh
#/usr/pluto/bin/sqlCVS -D pluto_telecom -u root -R 7999 -h localhost listen
/usr/pluto/bin/sqlCVS-server-myth.sh
#/usr/pluto/bin/sqlCVS -D myth_sqlcvs -u root -R 8999 -h localhost listen

log "All startup steps completed. Container is now idle."
tail -f /dev/null
EOS

# Docker Compose file
cat > "$container_dir/docker-compose.yml" <<EOF
services:
  $container_name:
    build: .
    container_name: $container_name
    restart: always
    ports:
      - 8080:80
      # - 3306:3306
      - 3999:3999
      - 4999:4999
      - 5999:5999
      - 6999:6999
      - 7999:7999
      - 8999:8999
    volumes:
      - "$container_dir/logs:/var/log:z"
      - "$container_dir/data:/var/lib/mysql:z"
EOF

# run.sh
cat > "$container_dir/run.sh" <<'EOS'
#!/bin/bash
cd "$(dirname "$0")"

action=${1:-start}

case $action in
  start)
    docker compose up -d --build
    tail -f logs/startup.log || :
    ;;
  stop)
    docker compose down
    ;;
  shell)
    docker exec -it sqlcvs-server bash
    ;;
  *)
    echo "Usage: $0 [start|stop|shell]"
    exit 1
    ;;
esac
EOS

chmod +x "$container_dir/run.sh"

# Complete message
echo "✅ sqlCVS server setup complete at $container_dir"

