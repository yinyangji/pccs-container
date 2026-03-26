#!/bin/sh
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

set -e

# Use `DOCKER=podman ./build_and_run_sample_docker.sh` for rootless Podman.
# 必须全程使用同一引擎：若用 podman 构建，run 也要 podman，否则镜像不在同一存储里。
DOCKER="${DOCKER:-podman}"
IMAGE_NAME="${IMAGE_NAME:-localhost/sgx_sample:latest}"
AESMD_NAME="${AESMD_NAME:-aesm-service}"
# 构建 debug enclave 时设为 1：SGX_SAMPLE_DEBUG=1 DOCKER=podman ./build_and_run_sample_docker.sh
SGX_SAMPLE_DEBUG="${SGX_SAMPLE_DEBUG:-0}"
# 测试结束后是否保留镜像：KEEP_IMAGE=1 表示不删除（默认删除以节省空间）
KEEP_IMAGE="${KEEP_IMAGE:-0}"

cleanup_image() {
  if [ "${KEEP_IMAGE}" = "1" ]; then
    return 0
  fi
  echo "Removing image: ${IMAGE_NAME}"
  "${DOCKER}" rmi -f "${IMAGE_NAME}" >/dev/null 2>&1 || true
}

"${DOCKER}" build --no-cache --target sample \
             --build-arg https_proxy=$https_proxy \
             --build-arg http_proxy=$http_proxy \
             --build-arg SGX_SAMPLE_DEBUG="${SGX_SAMPLE_DEBUG}" \
             -t "${IMAGE_NAME}" -f ./Dockerfile ./

# 构建成功后：测试结束（含 run 退出、Ctrl+C）时删除本脚本生成的镜像
trap cleanup_image EXIT INT TERM

# AESMD must already be running with the same volume (see build_and_run_aesm_docker.sh).
"${DOCKER}" volume inspect aesmd-socket >/dev/null 2>&1 || \
  "${DOCKER}" volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=rw aesmd-socket

if "${DOCKER}" inspect "${AESMD_NAME}" --type container >/dev/null 2>&1; then
  if ! "${DOCKER}" exec "${AESMD_NAME}" /bin/sh -c 'test -S /var/run/aesmd/aesm.socket' >/dev/null 2>&1; then
    echo "WARNING: ${AESMD_NAME} is running but /var/run/aesmd/aesm.socket is not ready yet."
    echo "  Wait for AESMD, or check: ${DOCKER} logs -f ${AESMD_NAME}"
  fi
else
  echo "WARNING: no container named ${AESMD_NAME}. Sample needs AESMD + aesmd-socket volume."
  echo "  Start AESMD first, e.g.: DOCKER=${DOCKER} ./build_and_run_aesm_docker.sh"
fi

# Sample needs the same SGX device nodes as AESM. EDMM path requires /dev/sgx_vepc.
# Legacy Launch Control: use only --device=/dev/isgx (omit sgx_provision/sgx_vepc per Intel).
DEVICE_ARGS="--device=/dev/sgx_enclave --device=/dev/sgx_provision"
if [ -e /dev/sgx_vepc ]; then
  DEVICE_ARGS="${DEVICE_ARGS} --device=/dev/sgx_vepc"
fi

# Podman rootless: inherit host supplementary groups (e.g. sgx) so non-root sgxuser can open devices.
KEEP_GROUPS=""
case "${DOCKER}" in podman) KEEP_GROUPS="--group-add keep-groups" ;; esac

# Rootless + SELinux: 与项目里其它脚本一致，避免卷/设备权限问题。
SECURITY_OPT="--security-opt label=disable"

# 无 TTY 时去掉 -t，避免 “cannot allocate pseudo-TTY” 之类错误。
if [ -t 0 ] && [ -t 1 ]; then
  IT="-it"
else
  IT="-i"
fi

# 更详细排查（Intel 官方 sample 对表内错误只打印固定英文，不打印十六进制）：
# - 重新构建本 Dockerfile 后，失败时 stderr 会多一行：sgx_create_enclave ret=0x...
# - AESMD：${DOCKER} logs -f ${AESMD_NAME}
# - 宿主机：dmesg | grep -i sgx
# - 系统调用（需自行装 strace / 用 root 跑），示例：
#   ${DOCKER} run --rm -it --user root ... ${IMAGE_NAME} sh -c 'apt-get update && apt-get install -y strace && su -s /bin/sh sgxuser -c "cd / && strace -f ./app"'

"${DOCKER}" run --rm ${IT} \
  --name sgx_sample \
  ${SECURITY_OPT} \
  --env http_proxy --env https_proxy \
  ${DEVICE_ARGS} \
  ${KEEP_GROUPS} \
  -v aesmd-socket:/var/run/aesmd:Z \
  "${IMAGE_NAME}"
