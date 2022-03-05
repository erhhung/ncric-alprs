# This user-data cloud-init script is a continuation
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
  mkfs.xfs -f -L elastic /dev/nvme1n1
  mkdir /opt/elasticsearch
  tab=$(printf "\t")
  cat <<EOF >> /etc/fstab
LABEL=elastic${tab}/opt/elasticsearch${tab}xfs${tab}defaults,nofail${tab}0 2
EOF
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
  [ -d data ] && exit
  mkdir -p data logs
  ln -s /etc/elasticsearch conf
  ln -s /usr/share/elasticsearch/bin
  ln -s /usr/share/elasticsearch/plugins

  cd conf
  mv elasticsearch.yml elasticsearch-default.yml
  aws s3 cp $ES_YML elasticsearch.yml
  cat <<'EOF' > jvm.options.d/heap.options
-Xms30g
-Xmx30g
EOF
  chown -Rh elasticsearch:elasticsearch \
    /opt/elasticsearch /etc/elasticsearch

  cd /etc/kibana
  mv kibana.yml kibana-default.yml
  aws s3 cp $KB_YML kibana.yml
  chmod 660 kibana.yml
  chown root:kibana *

  cd /etc/nginx
  run generate_cert
  mv /tmp/server.* .
  rm -f sites-enabled/default
  while read service listen port; do
    cat <<EOF > conf.d/$service.conf
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
elasticsearch 9200 9100
kibana        443  5601
EOT
)

start_elasticsearch() {
  systemctl daemon-reload
  for service in elasticsearch kibana nginx; do
    systemctl restart $service
    systemctl enable  $service
    systemctl status  $service --no-pager
  done
}

run install_java
run create_xfs_volume
run install_elasticsearch
run config_elasticsearch
run start_elasticsearch
