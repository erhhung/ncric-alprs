FROM ubuntu:22.04

LABEL name="maiveric/terraform"
LABEL description="MaiVERIC deployment environment with Terraform, Java, Python, and utilities like AWS CLI, jq and yq"

RUN apt-get update \
 && apt-get install -y curl wget less gnupg software-properties-common \
 # https://learn.hashicorp.com/tutorials/terraform/install-cli
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
 # https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
 && ( \
    cd /tmp; \
    curl -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip \
    && unzip -oq awscliv2.zip \
    && ./aws/install --update \
  ) \
 && mkdir -p /infra

ENV TF_CLI_ARGS_init="-compact-warnings -upgrade"
ENV TF_CLI_ARGS_plan="-compact-warnings"
ENV TF_CLI_ARGS_apply="-compact-warnings"

WORKDIR /infra

CMD bash
