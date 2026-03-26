FROM docker.1ms.run/library/ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG APT_MIRROR=aliyun
ARG DCAP_VERSION="1.25"
ARG PCCS_VERSION="1.25.100.1-noble1"

# 必须先安装 ca-certificates，再切到 HTTPS 镜像源；否则 apt 会报 “No system certificates available”。
# APT_MIRROR=aliyun 时写入 99no-verify：MITM/透明代理（如 Clash）下证书校验会失败（与仓库根 Dockerfile 一致）。
RUN set -e; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    if [ "${APT_MIRROR}" = "aliyun" ]; then \
      if [ -f /etc/apt/sources.list ]; then \
        sed -i \
          -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|https://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|https://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|http://ports.ubuntu.com/ubuntu-ports|https://mirrors.aliyun.com/ubuntu-ports|g' \
          -e 's|https://ports.ubuntu.com/ubuntu-ports|https://mirrors.aliyun.com/ubuntu-ports|g' \
          -e 's|^deb http://|deb https://|g' \
          -e 's|^deb-src http://|deb-src https://|g' \
          /etc/apt/sources.list; \
      fi; \
      if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i \
          -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|https://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|https://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|http://ports.ubuntu.com/ubuntu-ports|https://mirrors.aliyun.com/ubuntu-ports|g' \
          -e 's|https://ports.ubuntu.com/ubuntu-ports|https://mirrors.aliyun.com/ubuntu-ports|g' \
          -e 's|http://|https://|g' \
          /etc/apt/sources.list.d/ubuntu.sources; \
      fi; \
      echo 'Acquire::https::Verify-Peer "false"; Acquire::https::Verify-Host "false";' > /etc/apt/apt.conf.d/99no-verify; \
    else \
      if [ -f /etc/apt/sources.list ]; then \
        sed -i 's|^deb http://|deb https://|g; s|^deb-src http://|deb-src https://|g' /etc/apt/sources.list; \
      fi; \
      if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources; \
      fi; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends wget gnupg curl; \
    rm -rf /var/lib/apt/lists/*

RUN wget "https://download.01.org/intel-sgx/sgx-dcap/${DCAP_VERSION}/linux/distro/ubuntu24.04-server/sgx_debian_local_repo.tgz"

RUN tar zxvf sgx_debian_local_repo.tgz && \
    rm -f sgx_debian_local_repo.tgz

RUN echo "deb [trusted=yes arch=amd64] file:/sgx_debian_local_repo noble main" |\
    tee /etc/apt/sources.list.d/sgx_debian_local_repo.list

RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |\
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" |\
    tee /etc/apt/sources.list.d/nodesource.list

# The postinst will check the directory for configuration
RUN mkdir /etc/init/

RUN apt-get update && apt-get install -y nodejs cracklib-runtime sgx-dcap-pccs=${PCCS_VERSION} sgx-pck-id-retrieval-tool=${PCCS_VERSION} && \
    rm -rf /var/lib/apt/lists/*

RUN cd /opt/intel/sgx-dcap-pccs/ && \
    npm config set engine-strict true && \
    npm install

RUN mkdir /opt/intel/sgx-dcap-pccs/ssl_key

COPY default.json /opt/intel/sgx-dcap-pccs/config/
COPY network_setting.conf /opt/intel/sgx-pck-id-retrieval-tool/
COPY ssl_key/ /opt/intel/sgx-dcap-pccs/ssl_key/

WORKDIR /opt/intel/sgx-dcap-pccs/

EXPOSE 8081

CMD ["node", "pccs_server.js"]
