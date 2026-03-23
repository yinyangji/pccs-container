FROM docker.1ms.run/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      gnupg \
      wget && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x required by PCCS.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs cracklib-runtime && \
    rm -rf /var/lib/apt/lists/*

# Add Intel SGX apt repository (Ubuntu 24.04 / noble) and install PCCS package.
RUN mkdir -p /etc/apt/keyrings && \
    wget -qO- https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key \
      | tee /etc/apt/keyrings/intel-sgx-keyring.asc >/dev/null && \
    echo "deb [signed-by=/etc/apt/keyrings/intel-sgx-keyring.asc arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu noble main" \
      > /etc/apt/sources.list.d/intel-sgx.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends sgx-dcap-pccs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/intel/sgx-dcap-pccs

COPY container/entrypoint.sh /usr/local/bin/pccs-entrypoint.sh
RUN chmod +x /usr/local/bin/pccs-entrypoint.sh

EXPOSE 8081

ENTRYPOINT ["/usr/local/bin/pccs-entrypoint.sh"]
