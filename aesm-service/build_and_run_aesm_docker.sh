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

DOCKER="${DOCKER:-podman}"
IMAGE_NAME="${IMAGE_NAME:-localhost/sgx_aesm:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-aesm-service}"
AESMD_SOCKET_DIR="${AESMD_SOCKET_DIR:-$HOME/aesmd-shared}"
AESMD_SHARED_GROUP="${AESMD_SHARED_GROUP:-users}"

"${DOCKER}" build --target aesm --build-arg https_proxy=$https_proxy \
             --build-arg http_proxy=$http_proxy -t "${IMAGE_NAME}" -f ./Dockerfile ./

# Shared socket dir for cross-user access (group + ACL).
mkdir -p "${AESMD_SOCKET_DIR}"
chgrp "${AESMD_SHARED_GROUP}" "${AESMD_SOCKET_DIR}" 2>/dev/null || true
chmod 2770 "${AESMD_SOCKET_DIR}" || true
if command -v setfacl >/dev/null 2>&1; then
  setfacl -m "g:${AESMD_SHARED_GROUP}:rwx,d:g:${AESMD_SHARED_GROUP}:rwx" "${AESMD_SOCKET_DIR}" || true
fi

"${DOCKER}" rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

# If you use the Legacy Launch Control driver, replace /dev/sgx_enclave with /dev/isgx,
# and remove --device=/dev/sgx_provision / --device=/dev/sgx_vepc.
DEVICE_ARGS="--device=/dev/sgx_enclave --device=/dev/sgx_provision"
if [ -e /dev/sgx_vepc ]; then
  DEVICE_ARGS="${DEVICE_ARGS} --device=/dev/sgx_vepc"
fi

KEEP_GROUPS=""
case "${DOCKER}" in podman) KEEP_GROUPS="--group-add keep-groups --security-opt label=disable" ;; esac

"${DOCKER}" run -d --name "${CONTAINER_NAME}" \
  --env http_proxy --env https_proxy \
  ${KEEP_GROUPS} \
  ${DEVICE_ARGS} \
  -v /dev/log:/dev/log \
  -v "${AESMD_SOCKET_DIR}:/var/run/aesmd:Z" \
  -it "${IMAGE_NAME}"
