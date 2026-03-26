FROM docker.1ms.run/library/ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG APT_MIRROR=aliyun
ARG DCAP_VERSION="1.25"
ARG QGS_VERSION="1.25.100.1-noble1"

# 必须先安装 ca-certificates，再切 HTTPS 源；aliyun 时对 MITM 代理关闭 apt HTTPS 校验（与 pccs/Dockerfile 一致）。
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

RUN apt-get update && apt-get install -y \
    tdx-qgs=${QGS_VERSION} \
    libsgx-enclave-common-dev \
    libsgx-dcap-default-qpl \
    sgx-ra-service && \
    rm -rf /var/lib/apt/lists/*

COPY sgx_default_qcnl.conf /etc/

CMD ["/opt/intel/tdx-qgs/qgs", "--no-daemon"]
