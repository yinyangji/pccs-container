#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-local/sgx-pccs:ubuntu24.04}"
BUILD_NETWORK="${BUILD_NETWORK:-host}"
APT_MIRROR="${APT_MIRROR:-aliyun}"
PROXY_ARG=""
EXTRA_BUILD_ARGS=()

for a in "$@"; do
  case "$a" in
    --proxy=*)
      PROXY_ARG="${a#--proxy=}"
      ;;
    *)
      EXTRA_BUILD_ARGS+=("$a")
      ;;
  esac
done

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

echo "Building image: ${IMAGE_NAME}"
echo "Build network mode: ${BUILD_NETWORK}"
if [[ -n "${PROXY_ARG}" ]]; then
  echo "Build proxy mode: enabled (${PROXY_ARG})"
else
  echo "Build proxy mode: disabled"
fi
if [[ "${#EXTRA_BUILD_ARGS[@]}" -gt 0 ]]; then
  echo "Extra podman build args: ${EXTRA_BUILD_ARGS[*]}"
fi
for base_image in "${BASE_IMAGES_LIST[@]}"; do
  echo "Trying base image: ${base_image}"
  build_args=(--network "${BUILD_NETWORK}" --build-arg "BASE_IMAGE=${base_image}" --build-arg "APT_MIRROR=${APT_MIRROR}")
  if [[ -n "${PROXY_ARG}" ]]; then
    if [[ "${PROXY_ARG}" == *"://"* ]]; then
      PROXY_URL="${PROXY_ARG}"
    else
      PROXY_URL="http://${PROXY_ARG}"
    fi
    NO_PROXY_VALUE="localhost,127.0.0.1"
    build_args+=(
      --build-arg "HTTP_PROXY=${PROXY_URL}"
      --build-arg "http_proxy=${PROXY_URL}"
      --build-arg "HTTPS_PROXY=${PROXY_URL}"
      --build-arg "https_proxy=${PROXY_URL}"
      --build-arg "NO_PROXY=${NO_PROXY_VALUE}"
      --build-arg "no_proxy=${NO_PROXY_VALUE}"
    )
  fi

  if podman build "${build_args[@]}" "${EXTRA_BUILD_ARGS[@]}" -t "${IMAGE_NAME}" -f Dockerfile .; then
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
