#!/bin/bash

basedir=${basedir:-builders}
container_name="sqlcvs-server"
container_dir="$HOME/$basedir/$container_name"

mkdir -p "$container_dir"/{data,logs,www,lib,bin,scripts}

# Copy required archives from script dir to container_dir
cp sqlCVS-dbdump2025.tar.gz sqlCVS-server-scripts.tar sqlCVS-runtime-noble.tbz "$container_dir/"

cat > "$container_dir/Dockerfile" <<EOF
FROM ubuntu:noble

ENV DEBIAN_FRONTEND=noninteractive

# Install packages
RUN apt update && \
    apt install -y nano bzip2 apache2 php libapache2-mod-php mysql-server adminer screen git \
    && rm -rf /var/lib/apt/lists/*


# Adminer
RUN ln -s /usr/share/adminer/adminer /var/www/html/adminer.php

# Clone sqlCVSweb
RUN git clone https://github.com/linuxmce/sqlCVSweb.git /var/www/html/sqlCVS

# Ensure /usr/pluto directories exist
RUN mkdir -p /usr/pluto/bin /usr/pluto/lib

# Extract archives
COPY sqlCVS-dbdump2025.tar.gz sqlCVS-server-scripts.tar sqlCVS-runtime-noble.tgz /tmp/
RUN tar -xzf /tmp/sqlCVS-dbdump2025.tar.gz -C /tmp && \
    tar -xf /tmp/sqlCVS-server-scripts.tar --strip=1 -C /usr/pluto/bin && \
    chmod +x /usr/pluto/bin/* && \
    tar -xjf /tmp/sqlCVS-runtime-noble.tgz -C /tmp && \
    cp /tmp/usr/pluto/bin/sqlCVS /usr/pluto/bin/ && chmod +x /usr/pluto/bin/sqlCVS && \
    cp -r /tmp/usr/pluto/lib/* /usr/pluto/lib/ && \
    echo "/usr/pluto/lib" > /etc/ld.so.conf.d/pluto.conf && ldconfig

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

echo "========== Container Startup at $(date '+%Y-%m-%d %H:%M:%S') =========="
set -e

log "Ensuring MySQL log, run, and data directories exist"
# Ensure MySQL log, run, and data directories exist
mkdir -p /var/log/mysql /var/run/mysqld /var/lib/mysql
chown -R mysql:mysql /var/log/mysql /var/run/mysqld /var/lib/mysql

log "Checking for existing MySQL database"
# Initialize MySQL database if missing
initialized=false
if [ ! -d /var/lib/mysql/mysql ]; then
  log "Initializing MySQL data directory..."
  mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql || echo "MySQL initialization failed but continuing for container access"
  initialized=true
fi

log "Starting MySQL safely in background"
# Start MySQL safely in background
mysqld_safe --socket=/var/run/mysqld/mysqld.sock &

log "Waiting for MySQL to become available"
# Wait for MySQL to become available
until mysqladmin --socket=/var/run/mysqld/mysqld.sock ping --silent; do
  log "Waiting for MySQL..."
  sleep 2
  done
fi

if [ "$initialized" = true ]; then
  log "Securing root user to restrict access to localhost"
  # Secure root user and restrict to localhost
  mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY ''; FLUSH PRIVILEGES;"
fi

if [ "$initialized" = true ]; then
  log "Importing SQL dump files"
  # Import SQL dump files
  for sqlfile in /tmp/sqlCVS-dbdump2025/*.sql; do
  log "Importing database from: $sqlfile"
  dbname="$(basename "$sqlfile" .sql)"
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS $dbname; USE $dbname; SOURCE $sqlfile;"
done

log "Ensuring Apache log directory exists"
# Ensure Apache log directory exists
mkdir -p /var/log/apache2
chown -R www-data:www-data /var/log/apache2

log "Starting Apache"
# Start Apache
service apache2 start

log "Launching sqlCVS applications"
# Launch sqlCVS applications
#/usr/pluto/bin/sqlCVS -D myth_sqlcvs -u root -R 8999 -h localhost listen
#/usr/pluto/bin/sqlCVS -D main_sqlcvs_utf8 -u root -R 3999 -h localhost listen
#/usr/pluto/bin/sqlCVS -D pluto_security -u root -R 6999 -h localhost listen
#/usr/pluto/bin/sqlCVS -D pluto_telecom -u root -R 7999 -h localhost listen
#/usr/pluto/bin/sqlCVS -D pluto_media -u root -R 4999 -h localhost listen
#/usr/pluto/bin/sqlCVS -D lmce_game -u root -R 5999 -h localhost listen

log "All startup steps completed. Container is now idle."

# Keep the container running
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

