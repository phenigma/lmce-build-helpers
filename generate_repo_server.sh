#!/bin/bash

basedir=${basedir:-builders}
basedir=""
container_name="repo-server"
container_dir="$HOME/$basedir/$container_name"
host_port=${REPO_SERVER_PORT:-80}

mkdir -p "$container_dir/logs" "$container_dir/conf"

# Clean old files
echo rm -f "$container_dir/docker-compose.yml" "$container_dir/run.sh"
rm "$container_dir/docker-compose.yml" "$container_dir/run.sh"

# Generate docker-compose.yml
cat > "$container_dir/docker-compose.yml" <<EOF
services:
  $container_name:
    image: httpd:2.4
    container_name: $container_name
    restart: always
    ports:
      - "$host_port:80"
    volumes:
      - "$container_dir/logs:/usr/local/apache2/logs:z"
      - "$container_dir/conf:/usr/local/apache2/conf/extra:z"
EOF

# Process builder directories
mounts=""
urls=""
for dir in "$HOME/$basedir"/linuxmce-*; do
  [ -d "$dir/lmce-build/www" ] || continue

  repo=$(basename "$dir" | sed -E 's/linuxmce-[^-]+-(.+)/\1/')
  abs_path=$(realpath "$dir/lmce-build/www")

  mounts+="      - \"$abs_path:/usr/local/apache2/htdocs/$repo:z\"\n"
  urls+="http://\$host_ip:$host_port/$repo/\n"
done

# Insert mounts
sed -i "/volumes:/a\\
$mounts" "$container_dir/docker-compose.yml"

# Apache config enabling indexing and removing default page
cat > "$container_dir/conf/repo-server.conf" <<EOF
LoadModule autoindex_module modules/mod_autoindex.so

<Directory "/usr/local/apache2/htdocs">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

# run.sh script (fixed IP embedding and rebuild logic)
cat > "$container_dir/run.sh" <<'EOF'
#!/bin/bash

cd "$(dirname "$0")"

cmd=${1:---start}

get_host_ip() {
  hostname -I | awk '{print $1}'
}

case "$cmd" in
  --start)
    docker compose down >/dev/null 2>&1
    docker compose up -d --force-recreate
    sleep 3

    status=$(docker inspect -f '{{.State.Status}}' repo-server)
    if [ "$status" != "running" ]; then
      echo "Container failed to start. Logs:"
      docker compose logs
      exit 1
    fi

    # Remove default index.html
    docker exec repo-server rm -f /usr/local/apache2/htdocs/index.html

    host_ip=$(get_host_ip)
    echo "Repository server is accessible at:"
    echo -e "\nAvailable Repositories:"
    echo "
EOF

# Embed corrected URLs
printf '%b' "$urls" >> "$container_dir/run.sh"

cat >> "$container_dir/run.sh" <<'EOF'
"
    ;;
  --stop)
    docker compose down
    ;;
  --shell)
    docker exec -it repo-server bash
    ;;
  *)
    echo "Usage: $0 [--start|--stop|--shell]"
    exit 1
    ;;
esac
EOF

chmod +x "$container_dir/run.sh"

echo "✅ Setup completed in $container_dir"
