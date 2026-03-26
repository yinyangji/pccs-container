#!/bin/bash
#
# 构建 PCCS 镜像并启动容器（与 aesm-service/build_and_run_aesm_docker.sh 类似：build + run 一体）。
# 运行参数见本目录 README.md（1.2 Start PCCS Service）；并与 aesmd 容器共享 socket 卷 aesmd-socket。
#

set -euo pipefail

curr_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")
top_dir=$(dirname "${curr_dir}")

IMAGE_NAME="${IMAGE_NAME:-localhost/local/pccs-container:ubuntu24.04}"
CONTAINER_NAME="${CONTAINER_NAME:-pccs}"
AESMD_VOLUME="${AESMD_VOLUME:-aesmd-socket}"

action="all"
docker_build_clean_param=""
explicit_image=""
tag=""

usage() {
    cat << EOM
usage: $(basename "$0") [OPTION]...
  默认：构建镜像并启动容器（与 aesm-service/build_and_run_aesm_docker.sh 一致：先 build 再 run）。

  -a <all|build|run|publish|save>   默认 all（build + run）；build 仅构建；run 仅启动（需已有镜像）
  -t <tag>                          仅改 tag，镜像名为 localhost/local/pccs-container:<tag>
  -i <repo:tag>                     完整镜像名，优先级高于 -t 与环境变量 IMAGE_NAME
  -f                                docker build --no-cache
  -h                                帮助

环境变量：IMAGE_NAME、CONTAINER_NAME、AESMD_VOLUME（与 aesm-service 共用 aesmd socket 卷名，默认 aesmd-socket）
EOM
    exit 1
}

process_args() {
    local opt
    while getopts ":a:t:i:fh" opt; do
        case "${opt}" in
            a) action=${OPTARG} ;;
            t) tag=${OPTARG} ;;
            i) explicit_image=${OPTARG} ;;
            f) docker_build_clean_param="--no-cache" ;;
            h) usage ;;
            '?') echo "invalid option: -${OPTARG}" >&2; usage ;;
            :) echo "option -${OPTARG} requires an argument" >&2; usage ;;
        esac
    done

    if [[ ! "${action}" =~ ^(all|build|run|publish|save)$ ]]; then
        echo "invalid action: ${action}" >&2
        usage
    fi

    if [[ -n "${explicit_image}" ]]; then
        IMAGE_NAME="${explicit_image}"
    elif [[ -n "${tag}" ]]; then
        IMAGE_NAME="localhost/local/pccs-container:${tag}"
    fi
}

process_args "$@"

build_image() {
    if [ -f "${curr_dir}/pre-build.sh" ]; then
        echo "Execute pre-build script: ${curr_dir}/pre-build.sh"
        (cd "${curr_dir}" && ./pre-build.sh) || {
            echo "pre-build.sh failed" >&2
            exit 1
        }
    fi

    echo "Build => ${IMAGE_NAME}"
    cd "${top_dir}"
    if [[ -n "${docker_build_clean_param}" ]]; then
        docker build --no-cache \
            --build-arg http_proxy \
            --build-arg https_proxy \
            --build-arg no_proxy \
            -f "${curr_dir}/Dockerfile" \
            -t "${IMAGE_NAME}" \
            "${curr_dir}"
    else
        docker build \
            --build-arg http_proxy \
            --build-arg https_proxy \
            --build-arg no_proxy \
            -f "${curr_dir}/Dockerfile" \
            -t "${IMAGE_NAME}" \
            "${curr_dir}"
    fi

    echo "Done: ${IMAGE_NAME}"

    if [ -f "${curr_dir}/post-build.sh" ]; then
        echo "Execute post-build script: ${curr_dir}/post-build.sh"
        (cd "${curr_dir}" && ./post-build.sh) || {
            echo "post-build.sh failed" >&2
            exit 1
        }
    fi
}

# 与 aesm-service/build_and_run_aesm_docker.sh 使用同一卷名，便于 PCCS 挂载 /var/run/aesmd
ensure_aesmd_volume() {
    docker volume inspect "${AESMD_VOLUME}" >/dev/null 2>&1 \
        || docker volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=rw "${AESMD_VOLUME}"
}

# README.md 1.2；并挂载 aesmd socket（需先启动 aesm-service 容器写入 socket）
run_container() {
    ensure_aesmd_volume
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Run => ${CONTAINER_NAME} (${IMAGE_NAME})"
    docker run -d \
        --privileged \
        -v /sys/firmware/efi/:/sys/firmware/efi/ \
        -v "${AESMD_VOLUME}:/var/run/aesmd" \
        --name "${CONTAINER_NAME}" \
        --restart always \
        --net host \
        --env http_proxy \
        --env https_proxy \
        --env no_proxy \
        "${IMAGE_NAME}"
    echo "Started. Check: docker ps --filter name=${CONTAINER_NAME}"
    echo "Logs: docker logs -f ${CONTAINER_NAME}"
}

publish_image() {
    echo "Push ${IMAGE_NAME} ..."
    docker push "${IMAGE_NAME}"
}

save_image() {
    mkdir -p "${top_dir}/images"
    local base
    base=$(echo "${IMAGE_NAME}" | tr '/:' '_')
    docker save -o "${top_dir}/images/${base}.tar" "${IMAGE_NAME}"
    docker save "${IMAGE_NAME}" | gzip > "${top_dir}/images/${base}.tgz"
    echo "Saved: ${top_dir}/images/${base}.tar and .tgz"
}

echo ""
echo "-------------------------"
echo "action: ${action}"
echo "image:  ${IMAGE_NAME}"
echo "-------------------------"
echo ""

case "${action}" in
    all)
        build_image
        run_container
        ;;
    build)
        build_image
        ;;
    run)
        run_container
        ;;
    publish)
        publish_image
        ;;
    save)
        save_image
        ;;
esac
