# This user data script is a continuation
# of Elasticsearch's "boot.sh" script.

install_java() (
  hash java 2> /dev/null && exit
  apt-get install -y openjdk-11-jdk
  java --version
  cat <<'EOF' >> /etc/environment
ES_JAVA_HOME="/usr/lib/jvm/java-11-openjdk-arm64"
EOF
)

create_xfs_volume() (
  [ -d /opt/elasticsearch ] && exit
  if ! file -sL /dev/nvme1n1 | grep -q filesystem; then
    mkfs.xfs -f -L elastic /dev/nvme1n1
  fi
  tab=$(printf "\t")
  cat <<EOF >> /etc/fstab
LABEL=elastic${tab}/opt/elasticsearch${tab}xfs${tab}defaults,nofail${tab}0 2
EOF
  mkdir /opt/elasticsearch
  mount -a
  df -h /opt/elasticsearch
  cat <<'EOF' >> /etc/environment
ES_HOME="/opt/elasticsearch"
EOF
)

install_elasticsearch() (
  apt-get install -y apt-transport-https
  curl -s https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
  cat <<'EOF' > /etc/apt/sources.list.d/elastic-7.x.list
deb https://artifacts.elastic.co/packages/7.x/apt stable main
EOF
  apt-get update
  . /etc/environment
  apt-get install -y elasticsearch kibana nginx
  /usr/share/elasticsearch/bin/elasticsearch-plugin install analysis-phonetic
  sed -Ei '/^PATH=/s/(.*)"$/\1:\/usr\/share\/elasticsearch\/bin"/' /etc/environment
)

config_elasticsearch() (
  cd /etc/security/limits.d
  cat <<'EOF' > 10-defaults.conf
* soft nofile  300000
* hard nofile  300000
* hard memlock unlimited
* soft memlock unlimited
EOF
  cat <<'EOF' > 90-elasticsearch.conf
elasticsearch soft memlock unlimited
elasticsearch hard memlock unlimited
EOF
  cd /etc/systemd/system
  mkdir -p elasticsearch.service.d
  cat <<'EOF' > elasticsearch.service.d/override.conf
[Service]
LimitMEMLOCK=infinity
LimitNOFILE=300000
EOF
  cd /opt/elasticsearch
  if [ ! -d data ]; then
    mkdir data logs
    ln -s /etc/elasticsearch conf
    ln -s /usr/share/elasticsearch/bin
    ln -s /usr/share/elasticsearch/plugins
  fi

  cd conf
  mv elasticsearch.yml elasticsearch-default.yml
  aws s3 cp $ES_YML elasticsearch.yml
  heap_size=$(awk '/MemTotal.*kB/ {print int($2 /1024/1024 / 2)}' /proc/meminfo)
  cat <<EOF > jvm.options.d/heap.options
-Xms${heap_size}g
-Xmx${heap_size}g
EOF
  chown -Rh elasticsearch:elasticsearch \
    /opt/elasticsearch /etc/elasticsearch

  cd /etc/kibana
  mv kibana.yml kibana-default.yml
  aws s3 cp $KB_YML kibana.yml
  chmod 660 kibana.yml
  chown root:kibana *
)

restart_service() {
  systemctl restart $1
  systemctl enable  $1; sleep 10
  systemctl status  $1 --no-pager
  for port in ${@:2}; do
    # script will fail
    # if not listening
    nc -z localhost $port
  done
}

start_elasticsearch() {
  systemctl daemon-reload
  restart_service elasticsearch 9201 9301
  restart_service kibana        5601
}

config_nginx() (
  cd /etc/nginx
  run generate_cert
  mv /tmp/server.* .
  # disable unused modules and site
  find modules-enabled/ -mindepth 1 | \
    grep -v stream | xargs rm -f
  rm -f sites-enabled/default

  aws s3 cp $NG_CONF nginx.conf
  while read service listen port; do
    cat <<EOF > conf.d/http_$service.conf
# https://docs.nginx.com/nginx/admin-guide/load-balancer/http-load-balancer/
server {
  listen              $listen ssl default_server;
  ssl_certificate     /etc/nginx/server.crt;
  ssl_certificate_key /etc/nginx/server.key;
  server_name         $(curl -s http://169.254.169.254/latest/meta-data/local-hostname);

  location / {
    proxy_pass http://localhost:$port;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF
  done <<'EOT'
es_rest 9200 9201
kibana  443  5601
EOT
  while read service listen port; do
    cat <<EOF > conf.d/stream_$service.conf
# https://docs.nginx.com/nginx/admin-guide/load-balancer/tcp-udp-load-balancer/
server {
  listen     $listen;
  proxy_pass localhost:$port;
}
EOF
  done <<'EOT'
es_transport 9300 9301
EOT
)

start_nginx() {
  restart_service nginx 443 9200 9300
}

run install_java
run create_xfs_volume
run install_elasticsearch
run config_elasticsearch
run start_elasticsearch
run config_nginx
run start_nginx
