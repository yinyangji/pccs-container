#!/bin/bash
#
# 构建 AESM 镜像并启动容器（结构与 pccs/build_and_run_pccs_docker.sh 一致）。
# 使用宿主机目录 AESMD_SOCKET_DIR（默认 ~/aesmd-shared）绑定 /var/run/aesmd，勿使用命名卷。
#

set -euo pipefail

curr_dir=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")
top_dir=$(dirname "${curr_dir}")

IMAGE_NAME="${IMAGE_NAME:-localhost/sgx_aesm:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-aesm-service}"
AESMD_SOCKET_DIR="${AESMD_SOCKET_DIR:-$HOME/aesmd-shared}"
AESMD_SHARED_GROUP="${AESMD_SHARED_GROUP:-users}"
DOCKER="${DOCKER:-podman}"
AESM_MOUNT_DEV_LOG="${AESM_MOUNT_DEV_LOG:-0}"
# 与 pccs 一致：Dockerfile 内 Ubuntu 源；aliyun（默认）或 official
APT_MIRROR="${APT_MIRROR:-aliyun}"
# 1 / yes：删除镜像后强制重建；或命令行 -F；或环境变量 FORCE_BUILD / AESM_FORCE_BUILD
FORCE_REBUILD="${FORCE_BUILD:-${AESM_FORCE_BUILD:-0}}"

# docker build：本机代理时自动 --network host（与 PCCS 脚本一致）
aesm_docker_build_network_array() {
    docker_build_net=()
    case "${BUILD_NETWORK:-auto}" in
        host)
            echo "${DOCKER} build 使用 --network=host（BUILD_NETWORK=host）。" >&2
            docker_build_net=(--network host)
            ;;
        bridge)
            ;;
        auto)
            local _p="${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}"
            if [[ "${_p}" =~ 127\.0\.0\.1|localhost ]]; then
                echo "检测到代理指向本机；docker build 使用 --network=host。" >&2
                docker_build_net=(--network host)
            fi
            ;;
        *)
            docker_build_net=(--network "${BUILD_NETWORK}")
            ;;
    esac
}

action="all"
docker_build_clean_param=""
explicit_image=""
tag=""
force_rebuild_flag="0"

usage() {
    cat << EOM
usage: $(basename "$0") [OPTION]...
  默认 all：按需构建镜像（已存在则跳过，除非 -F）并启动容器。

  -a <all|build|run|publish|save>   默认 all；build 仅构建；run 仅启动（需已有镜像）
  -t <tag>                          镜像名 localhost/sgx_aesm:<tag>
  -i <repo:tag>                     完整镜像名，覆盖 -t 与 IMAGE_NAME
  -f                                docker build --no-cache
  -F                                强制删除已有镜像后重建
  -h                                帮助

  环境变量：IMAGE_NAME、CONTAINER_NAME、AESMD_SOCKET_DIR（默认 \$HOME/aesmd-shared）
           AESMD_SHARED_GROUP（默认 users）、DOCKER（默认 podman）
           APT_MIRROR（默认 aliyun，构建时传入 Dockerfile）
           BUILD_NETWORK、AESM_MOUNT_DEV_LOG（1 时挂载 /dev/log）
           FORCE_BUILD / AESM_FORCE_BUILD（1 时等同 -F）
EOM
    exit 1
}

process_args() {
    local opt
    while getopts ":a:t:i:fFh" opt; do
        case "${opt}" in
            a) action=${OPTARG} ;;
            t) tag=${OPTARG} ;;
            i) explicit_image=${OPTARG} ;;
            f) docker_build_clean_param="--no-cache" ;;
            F) force_rebuild_flag="1" ;;
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
        IMAGE_NAME="localhost/sgx_aesm:${tag}"
    fi

    if [[ "${force_rebuild_flag}" == "1" ]] || [[ "${FORCE_REBUILD}" == "1" ]] || [[ "${FORCE_REBUILD}" == "yes" ]] || [[ "${FORCE_REBUILD}" == "true" ]]; then
        force_rebuild_flag="1"
    fi
}

process_args "$@"

aesm_image_exists() {
    "${DOCKER}" image inspect "${IMAGE_NAME}" >/dev/null 2>&1
}

# 与 pccs/build_and_run_pccs_docker.sh 相同，便于 host 进程使用 aesm.socket
ensure_aesmd_socket_dir() {
    mkdir -p "${AESMD_SOCKET_DIR}"
    chgrp "${AESMD_SHARED_GROUP}" "${AESMD_SOCKET_DIR}" 2>/dev/null || true
    chmod 2770 "${AESMD_SOCKET_DIR}" || true
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -m "g:${AESMD_SHARED_GROUP}:rwx,d:g:${AESMD_SHARED_GROUP}:rwx" "${AESMD_SOCKET_DIR}" || true
    fi
}

build_image() {
    echo "Build => ${IMAGE_NAME} (target aesm)"
    cd "${curr_dir}"
    aesm_docker_build_network_array

    if [[ "${force_rebuild_flag}" == "1" ]]; then
        echo "Force rebuild: removing ${IMAGE_NAME} ..."
        "${DOCKER}" rmi -f "${IMAGE_NAME}" 2>/dev/null || true
    fi

    if [[ "${force_rebuild_flag}" == "1" ]] || ! aesm_image_exists; then
        if [[ -n "${docker_build_clean_param}" ]]; then
            "${DOCKER}" build --no-cache \
                "${docker_build_net[@]}" \
                --target aesm \
                --build-arg APT_MIRROR="${APT_MIRROR}" \
                --build-arg http_proxy \
                --build-arg https_proxy \
                --build-arg no_proxy \
                --build-arg HTTP_PROXY \
                --build-arg HTTPS_PROXY \
                --build-arg NO_PROXY \
                -f "${curr_dir}/Dockerfile" \
                -t "${IMAGE_NAME}" \
                "${curr_dir}"
        else
            "${DOCKER}" build \
                "${docker_build_net[@]}" \
                --target aesm \
                --build-arg APT_MIRROR="${APT_MIRROR}" \
                --build-arg http_proxy \
                --build-arg https_proxy \
                --build-arg no_proxy \
                --build-arg HTTP_PROXY \
                --build-arg HTTPS_PROXY \
                --build-arg NO_PROXY \
                -f "${curr_dir}/Dockerfile" \
                -t "${IMAGE_NAME}" \
                "${curr_dir}"
        fi
        echo "Done: ${IMAGE_NAME}"
    else
        echo "Image ${IMAGE_NAME} already exists, skip build (use -F or FORCE_BUILD=1 to rebuild)."
    fi
}

run_container() {
    ensure_aesmd_socket_dir
    "${DOCKER}" rm -f "${CONTAINER_NAME}" 2>/dev/null || true

    DEVICE_ARGS=(--device=/dev/sgx_enclave --device=/dev/sgx_provision)
    if [[ -e /dev/sgx_vepc ]]; then
        DEVICE_ARGS+=(--device=/dev/sgx_vepc)
    fi

    PODMAN_SECURITY=()
    case "${DOCKER}" in
        podman) PODMAN_SECURITY=(--security-opt label=disable) ;;
    esac

    DEV_LOG_VOL=()
    if [[ "${AESM_MOUNT_DEV_LOG}" == "1" ]]; then
        DEV_LOG_VOL=(-v /dev/log:/dev/log)
    fi

    echo "Run => ${CONTAINER_NAME} (${IMAGE_NAME})  aesmd: ${AESMD_SOCKET_DIR}"
    "${DOCKER}" run -d \
        "${PODMAN_SECURITY[@]}" \
        "${DEVICE_ARGS[@]}" \
        "${DEV_LOG_VOL[@]}" \
        --restart unless-stopped \
        --privileged \
        --env http_proxy \
        --env https_proxy \
        -v "${AESMD_SOCKET_DIR}:/var/run/aesmd:Z" \
        --name "${CONTAINER_NAME}" \
        "${IMAGE_NAME}"

    echo "Started. Check: ${DOCKER} ps --filter name=${CONTAINER_NAME}"
    echo "Host socket: ls -l \"${AESMD_SOCKET_DIR}/aesm.socket\""
}

publish_image() {
    echo "Push ${IMAGE_NAME} ..."
    "${DOCKER}" push "${IMAGE_NAME}"
}

save_image() {
    mkdir -p "${top_dir}/images"
    local base
    base=$(echo "${IMAGE_NAME}" | tr '/:' '_')
    "${DOCKER}" save -o "${top_dir}/images/${base}.tar" "${IMAGE_NAME}"
    "${DOCKER}" save "${IMAGE_NAME}" | gzip > "${top_dir}/images/${base}.tgz"
    echo "Saved: ${top_dir}/images/${base}.tar and .tgz"
}

echo ""
echo "-------------------------"
echo "action: ${action}"
echo "image:  ${IMAGE_NAME}"
echo "aesmd:  ${AESMD_SOCKET_DIR}"
echo "apt:    APT_MIRROR=${APT_MIRROR}"
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
