FROM ubuntu:22.04

LABEL name="maiveric/terraform"
LABEL description="MaiVERIC deployment environment with Terraform, Java, Python, and utilities like jq and yq"

# https://learn.hashicorp.com/tutorials/terraform/install-cli

RUN apt-get update \
 && apt-get install -y curl wget gnupg software-properties-common \
 && ( \
    apt_url="https://apt.releases.hashicorp.com"; \
    keyring="/usr/share/keyrings/hashicorp-archive-keyring.gpg"; \
    sources="/etc/apt/sources.list.d/hashicorp.list"; \
    curl -s "$apt_url/gpg" | gpg --dearmor > $keyring \
    && echo "deb [signed-by=$keyring] $apt_url $(lsb_release -cs) main" > $sources \
    && apt-get update \
    && apt-get install -y terraform \
 ) \
 && apt-get install -y zip unzip pwgen gettext jq \
 && ( \
    VERSION=v4.27.2; \
    case $(uname -m) in \
       x86_64) ARCH=linux_amd64 ;; \
      aarch64) ARCH=linux_arm64 ;; \
    esac; \
    yq_url="https://github.com/mikefarah/yq/releases/download/$VERSION/yq_$ARCH"; \
    curl -sLo   /usr/bin/yq $yq_url \
    && chmod +x /usr/bin/yq \
 ) \
 && apt-get install -y python3-pip openjdk-11-jdk \
 && mkdir -p /infra

WORKDIR /infra

CMD bash
