#
# Copyright (C) 2020 Intel Corporation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#   * Neither the name of Intel Corporation nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#


FROM ubuntu:24.04 as sgxbase
RUN sed -i 's@archive.ubuntu.com@mirrors.aliyun.com@g' /etc/apt/sources.list.d/ubuntu.sources \
    && sed -i 's@security.ubuntu.com@mirrors.aliyun.com@g' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update && apt-get install -y \
    gnupg \
    wget

RUN echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu noble main' > /etc/apt/sources.list.d/intel-sgx.list
RUN wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | apt-key add -
RUN apt-get update 

FROM sgxbase as sgx_sample_builder
# App build time dependencies
RUN apt-get install -y build-essential

# 0=release enclave, 1=debug enclave（便于排查；HW 下 Intel sample 仍支持）
ARG SGX_SAMPLE_DEBUG=0

WORKDIR /opt/intel
RUN wget https://download.01.org/intel-sgx/latest/linux-latest/distro/ubuntu24.04-server/sgx_linux_x64_sdk_2.28.100.1.bin
RUN chmod +x sgx_linux_x64_sdk_2.28.100.1.bin
RUN echo 'yes' | ./sgx_linux_x64_sdk_2.28.100.1.bin
WORKDIR /opt/intel/sgxsdk/SampleCode/SampleEnclave
# fprintf 需要 stdio（若 sample 未直接包含则补上）
RUN grep -qF '#include <stdio.h>' App/App.cpp || sed -i '1i#include <stdio.h>' App/App.cpp
# Intel 官方 sample 对表内错误只打印固定英文，不打印十六进制；这里补上 ret，便于对照《Developer Reference》
RUN sed -i \
  's/print_error_message(ret);/fprintf(stderr, "sgx_create_enclave ret=%#x\\n", (unsigned int)ret); print_error_message(ret);/' \
  App/App.cpp
RUN SGX_DEBUG=${SGX_SAMPLE_DEBUG} SGX_MODE=HW SGX_PRERELEASE=1 make

FROM sgxbase as sample
RUN apt-get install -y \
    libcurl4-openssl-dev \
    libprotobuf-dev \
    libssl-dev

# No AESM daemon, only AESM client side API support for launch.
# For applications requiring attestation, add libsgx-quote-ex
RUN apt-get install -y --no-install-recommends libsgx-urts

COPY --from=sgx_sample_builder /opt/intel/sgxsdk/SampleCode/SampleEnclave/app .
COPY --from=sgx_sample_builder /opt/intel/sgxsdk/SampleCode/SampleEnclave/enclave.signed.so .

RUN adduser -q --disabled-password --gecos "" --no-create-home sgxuser \
    && (getent group sgx >/dev/null || groupadd -r sgx) \
    && usermod -aG sgx sgxuser
USER sgxuser
CMD ./app

FROM sgxbase as aesm 
RUN apt-get install -y \
    libcurl4-openssl-dev \
    libprotobuf-dev \
    libssl-dev \
    make

# More aesm plugins are needed if application requires attestation. See installation guide.
RUN apt-get install -y libsgx-aesm-quote-ex-plugin

WORKDIR /opt/intel/sgx-aesm-service/aesm
ENV LD_LIBRARY_PATH=.
CMD ./aesm_service --no-daemon

