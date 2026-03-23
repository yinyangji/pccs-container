ARG BASE_IMAGE=docker.1ms.run/library/ubuntu:24.04
FROM ${BASE_IMAGE}

ARG APT_MIRROR=aliyun

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy

ENV DEBIAN_FRONTEND=noninteractive
ENV HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    no_proxy=${no_proxy}

#
# Apt mirror selection.
# - If APT_MIRROR=aliyun: switch archive/security mirrors to mirrors.aliyun.com (HTTPS)
# - Otherwise: keep upstream but force HTTPS (avoid HTTP/80 blocked in restricted networks)
#
RUN set -e; \
    if [ "${APT_MIRROR}" = "aliyun" ]; then \
      if [ -f /etc/apt/sources.list ]; then \
        sed -i \
          -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|https://archive.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
          -e 's|https://security.ubuntu.com/ubuntu|https://mirrors.aliyun.com/ubuntu|g' \
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
          -e 's|http://|https://|g' \
          /etc/apt/sources.list.d/ubuntu.sources; \
      fi; \
      # If host side uses MITM proxy (e.g. Clash) the CA may not be trusted inside build container.
      # Disable HTTPS verification for apt so `apt-get update` can still proceed.
      echo 'Acquire::https::Verify-Peer "false"; Acquire::https::Verify-Host "false";' > /etc/apt/apt.conf.d/99no-verify; \
    else \
      if [ -f /etc/apt/sources.list ]; then \
        sed -i 's|^deb http://|deb https://|g; s|^deb-src http://|deb-src https://|g' /etc/apt/sources.list; \
      fi && \
      if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources; \
      fi; \
    fi

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      gnupg \
      sudo \
      bash \
      wget && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x required by PCCS.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs cracklib-runtime && \
    rm -rf /var/lib/apt/lists/*

# Container use-case: allow sudo without password for convenience.
# NOTE: this is less secure, but common for single-purpose dev/test containers.
RUN echo 'ALL ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-container-nopasswd && chmod 440 /etc/sudoers.d/99-container-nopasswd

#
# PCCS/SGX packages are intentionally not installed during image build.
# You can install them later inside the container (this image is mainly
# a runtime + tooling environment + entrypoint).
#
WORKDIR /root

COPY container/entrypoint.sh /usr/local/bin/pccs-entrypoint.sh
RUN chmod +x /usr/local/bin/pccs-entrypoint.sh

EXPOSE 8081

ENTRYPOINT ["/usr/local/bin/pccs-entrypoint.sh"]
