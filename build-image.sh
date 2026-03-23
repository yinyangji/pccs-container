#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-local/sgx-pccs:ubuntu24.04}"
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

for base_image in "${BASE_IMAGES_LIST[@]}"; do
  echo "Trying base image: ${base_image}"
  if podman build --build-arg "BASE_IMAGE=${base_image}" -t "${IMAGE_NAME}" -f Dockerfile .; then
    echo "Build completed with base image: ${base_image}"
    exit 0
  fi
  echo "Build failed with base image: ${base_image}"
done

echo "ERROR: all candidate base images failed."
exit 1
