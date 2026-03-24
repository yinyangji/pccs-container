#!/usr/bin/env bash
set -euo pipefail

# 构建目标：单容器（pccs+aesmd）
IMAGE_NAME="${IMAGE_NAME:-localhost/local/sgx-pccs-aesmd:ubuntu24.04}"
BUILD_NETWORK="${BUILD_NETWORK:-host}"
APT_MIRROR="${APT_MIRROR:-aliyun}"
PROXY_ARG=""
EXTRA_BUILD_ARGS=()

args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  a="${args[$i]}"
  case "$a" in
    --proxy=*)
      PROXY_ARG="${a#--proxy=}"
      ;;
    *)
      EXTRA_BUILD_ARGS+=("$a")
      ;;
  esac
  i=$((i + 1))
done

DOCKERFILE="Dockerfile"
BUILD_CONTEXT="."

# PCCS 镜像多次构建可能会因为旧层缓存导致 ENTRYPOINT/文件缺失等问题，
# 所以默认总是使用 --no-cache（除非你显式传入一个包含 --no-cache 的参数集）。
if [[ ! " ${EXTRA_BUILD_ARGS[*]} " =~ " --no-cache " ]]; then
  EXTRA_BUILD_ARGS+=(--no-cache)
fi
echo "Using podman build option: --no-cache"

BASE_IMAGES_DEFAULT=(
  "docker.1ms.run/library/ubuntu:24.04"
  "ubuntu:24.04"
)

if [[ -n "${BASE_IMAGES:-}" ]]; then
  # Comma-separated override, e.g. BASE_IMAGES="docker.1ms.run/library/ubuntu:24.04,ubuntu:24.04"
  IFS=',' read -r -a BASE_IMAGES_LIST <<< "${BASE_IMAGES}"
else
  BASE_IMAGES_LIST=("${BASE_IMAGES_DEFAULT[@]}")
fi

echo "Building image: ${IMAGE_NAME} (single container: pccs+aesmd)"
echo "Dockerfile: ${DOCKERFILE}"
echo "Build network mode: ${BUILD_NETWORK}"
if [[ -n "${PROXY_ARG}" ]]; then
  echo "Build proxy mode: enabled (${PROXY_ARG})"
else
  echo "Build proxy mode: disabled"
fi
if [[ "${#EXTRA_BUILD_ARGS[@]}" -gt 0 ]]; then
  echo "Extra podman build args: ${EXTRA_BUILD_ARGS[*]}"
fi

do_build() {
  local base_image="$1"
  local build_args=()
  build_args+=(--network "${BUILD_NETWORK}")
  build_args+=(--build-arg "BASE_IMAGE=${base_image}" --build-arg "APT_MIRROR=${APT_MIRROR}")
  if [[ -n "${PROXY_ARG}" ]]; then
    local proxy_url
    if [[ "${PROXY_ARG}" == *"://"* ]]; then
      proxy_url="${PROXY_ARG}"
    else
      proxy_url="http://${PROXY_ARG}"
    fi
    build_args+=(
      --build-arg "HTTP_PROXY=${proxy_url}"
      --build-arg "http_proxy=${proxy_url}"
      --build-arg "HTTPS_PROXY=${proxy_url}"
      --build-arg "https_proxy=${proxy_url}"
      --build-arg "NO_PROXY=localhost,127.0.0.1"
      --build-arg "no_proxy=localhost,127.0.0.1"
    )
  fi
  build_args+=(-f "${DOCKERFILE}" -t "${IMAGE_NAME}" "${BUILD_CONTEXT}")
  podman build "${build_args[@]}" "${EXTRA_BUILD_ARGS[@]}"
}

# Single-image build: try multiple base images
for base_image in "${BASE_IMAGES_LIST[@]}"; do
  echo "Trying base image: ${base_image}"
  if do_build "${base_image}"; then
    echo "Build completed with base image: ${base_image}"
    echo "Verifying image contains bash..."
    if ! podman run --rm --entrypoint /bin/sh "${IMAGE_NAME}" -c 'test -x /bin/bash'; then
      echo "ERROR: /bin/bash not found in image."
      exit 1
    fi
    echo "Image verification passed."
    exit 0
  fi
  echo "Build failed with base image: ${base_image}"
done

echo "ERROR: all candidate base images failed."
exit 1
