#!/bin/bash

# 默认在「最小 Ubuntu」rootless podman 容器内执行本脚本，宿主机无需 sudo、无需安装 cracklib/openssl。
# 流程：容器内先 apt 装依赖（非交互）→ 再执行同一份 pre-build.sh 后半段，与宿主机直接运行时的交互问答一致。
# 跳过容器（在宿主机直接跑）：PCCS_PREBUILD_USE_HOST=1 ./pre-build.sh
# 自定义基础镜像（需含 bash，或仍由下方 apt 安装依赖）：PCCS_PREBUILD_IMAGE=...
# 镜像里已有所需包、跳过 apt：PCCS_PREBUILD_SKIP_APT=1 ./pre-build.sh
#
if [[ "${PCCS_PREBUILD_USE_HOST:-0}" != "1" && "${PCCS_PREBUILD_IN_CONTAINER:-0}" != "1" ]]; then
    PCCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! command -v podman >/dev/null 2>&1; then
        echo "未找到 podman。请安装 rootless podman，或执行: PCCS_PREBUILD_USE_HOST=1 $0" >&2
        exit 1
    fi
    PREBUILD_IMAGE="${PCCS_PREBUILD_IMAGE:-docker.1ms.run/library/ubuntu:24.04}"
    echo "--------------------------------"
    echo "在 rootless podman 容器内配置 PCCS（宿主机无需 sudo）"
    echo "镜像: ${PREBUILD_IMAGE}"
    echo "挂载: ${PCCS_DIR} -> /work"
    echo "若要在宿主机直接运行: PCCS_PREBUILD_USE_HOST=1 $0"
    echo "--------------------------------"
    exec podman run --rm -it \
        --security-opt label=disable \
        -v "${PCCS_DIR}:/work:Z" \
        -w /work \
        -e PCCS_PREBUILD_IN_CONTAINER=1 \
        -e PCCS_SKIP_CRACKLIB \
        -e PCCS_MIN_PASSWORD_LEN \
        -e PCCS_PREBUILD_SKIP_APT \
        -e http_proxy -e https_proxy -e no_proxy \
        -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY \
        "${PREBUILD_IMAGE}" \
        bash -c 'set -e
# 仅 apt 阶段使用 noninteractive；装完后取消，避免影响 openssl 等后续交互
if [[ "${PCCS_PREBUILD_SKIP_APT:-0}" != "1" ]]; then
  if [ -n "${http_proxy:-}" ]; then
    printf "Acquire::http::Proxy \"%s\";\n" "$http_proxy" > /etc/apt/apt.conf.d/98proxy.conf
  fi
  if [ -n "${https_proxy:-}" ]; then
    printf "Acquire::https::Proxy \"%s\";\n" "$https_proxy" >> /etc/apt/apt.conf.d/98proxy.conf
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    bash sed ca-certificates openssl coreutils cracklib-runtime
  unset DEBIAN_FRONTEND
else
  echo "PCCS_PREBUILD_SKIP_APT=1: 跳过 apt，请确保镜像内已有 bash sed openssl cracklib 等依赖。"
fi
echo ""
echo "--------------------------------"
echo "依赖已就绪。下面进入 PCCS 交互配置（平台 liv/sbx、端口、API Key、管理员/用户口令、证书等），与宿主机直接执行本脚本相同。"
echo "--------------------------------"
echo ""
exec bash /work/pre-build.sh'
fi

## Set mydir to the directory containing the script
configFile=default.json
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# 若未安装 cracklib-runtime，则没有 cracklib-check；此时不能误判为「弱密码」。
# 回退为仅检查长度（默认 >=8，可用 PCCS_MIN_PASSWORD_LEN 覆盖）。
# PCCS_SKIP_CRACKLIB=1 时跳过一切强度检查。
pccs_check_password_strength() {
    local pw="$1"
    if [[ "${PCCS_SKIP_CRACKLIB:-0}" == "1" ]]; then
        return 0
    fi
    if ! command -v cracklib-check >/dev/null 2>&1; then
        if [[ "${PCCS_CRACKLIB_FALLBACK_WARNED:-0}" != "1" ]]; then
            echo -e "${YELLOW}cracklib-check not found (install package cracklib-runtime). Using length-only check (>= ${PCCS_MIN_PASSWORD_LEN:-8} chars).${NC}"
            PCCS_CRACKLIB_FALLBACK_WARNED=1
        fi
        if [[ ${#pw} -ge ${PCCS_MIN_PASSWORD_LEN:-8} ]]; then
            return 0
        fi
        echo "Password too short (need >= ${PCCS_MIN_PASSWORD_LEN:-8} characters)."
        return 1
    fi
    local result okay
    result="$(cracklib-check <<<"$pw" 2>/dev/null)" || true
    okay="$(awk -F': ' '{ print $NF}' <<<"$result")"
    if [[ "$okay" != "OK" ]]; then
        echo "cracklib-check: ${result}"
        return 1
    fi
    return 0
}

echo "--------------------------------"
echo "Start to setup pccs configuration"

#Ask for URI
platform=""
while :
do
    read -rp "Choose your Platform (liv/sbx) :" platform 
    if [ "$platform" == "liv" ]
    then
        sed "/\"uri\"*/c\ \ \ \ \"uri\" \: \"https://api.trustedservices.intel.com/sgx/certification/v4/\"," -i ${configFile}
        break
    elif [ "$platform" == "sbx" ]
    then
        sed "/\"uri\"*/c\ \ \ \ \"uri\" \: \"https://sbx.api.trustedservices.intel.com/sgx/certification/v4/\"," -i ${configFile}
        break
    else
        echo "Your input is invalid. Please input again. "
    fi
done


#Ask for proxy server
echo "Check proxy server configuration for internet connection... "
if [ "$http_proxy" == "" ]
then
    read -rp "Enter your http proxy server address, e.g. http://proxy-server:port (Press ENTER if there is no proxy server) :" http_proxy 
fi
if [ "$https_proxy" == "" ]
then
    read -rp "Enter your https proxy server address, e.g. http://proxy-server:port (Press ENTER if there is no proxy server) :" https_proxy 
fi


#Ask for HTTPS port number
port=""
while :
do
    read -rp "Set HTTPS listening port [8081] (1024-65535) :" port
    if [ -z "$port" ]; then 
        port=8081
        break
    elif [[ $port -lt 1024  ||  $port -gt 65535 ]] ; then
        echo -e "${YELLOW}The port number is out of range, please input again.${NC} "
    else
        sed "/\"HTTPS_PORT\"*/c\ \ \ \ \"HTTPS_PORT\" \: ${port}," -i ${configFile}
        break
    fi
done

#Ask for HTTPS port number
local_only=""
while [ "$local_only" == "" ]
do
    read -rp "Set the PCCS service to accept local connections only? [Y] (Y/N) :" local_only 
    if [[ -z $local_only  || "$local_only" == "Y" || "$local_only" == "y" ]] 
    then
        local_only="Y"
        sed "/\"hosts\"*/c\ \ \ \ \"hosts\" \: \"127.0.0.1\"," -i ${configFile}
    elif [[ "$local_only" == "N" || "$local_only" == "n" ]] 
    then
        sed "/\"hosts\"*/c\ \ \ \ \"hosts\" \: \"0.0.0.0\"," -i ${configFile}
    else
        local_only=""
    fi
done

#Ask for API key 
apikey=""
while :
do
    read -rp "Set your Intel PCS API key (Press ENTER to skip) :" apikey 
    if [ -z "$apikey" ]
    then
        echo -e "${YELLOW}You didn't set Intel PCS API key. You can set it later in config/default.json. ${NC} "
        break
    elif [[ $apikey =~ ^[a-zA-Z0-9]{32}$ ]] && sed "/\"ApiKey\"*/c\ \ \ \ \"ApiKey\" \: \"${apikey}\"," -i ${configFile}
    then
        break
    else
        echo "Your API key is invalid. Please input again. "
    fi
done

if [ "$https_proxy" != "" ]
then
    sed "/\"proxy\"*/c\ \ \ \ \"proxy\" \: \"${https_proxy}\"," -i ${configFile}
fi

#Ask for CachingFillMode
caching_mode=""
while [ "$caching_mode" == "" ]
do
    read -rp "Choose caching fill method : [LAZY] (LAZY/OFFLINE/REQ) :" caching_mode 
    if [[ -z $caching_mode  || "$caching_mode" == "LAZY" ]] 
    then
        caching_mode="LAZY"
        sed "/\"CachingFillMode\"*/c\ \ \ \ \"CachingFillMode\" \: \"${caching_mode}\"," -i ${configFile}
    elif [[ "$caching_mode" == "OFFLINE" || "$caching_mode" == "REQ" ]] 
    then
        sed "/\"CachingFillMode\"*/c\ \ \ \ \"CachingFillMode\" \: \"${caching_mode}\"," -i ${configFile}
    else
        caching_mode=""
    fi
done

#Ask for administrator password
# 明文输入便于核对。若已安装 cracklib-check，会做字典强度检查；否则仅检查长度。
# PCCS_SKIP_CRACKLIB=1 可跳过强度检查（不推荐生产环境）。
admintoken1=""
admintoken2=""
admin_pass_set=false
cracklib_limit=4
while [ "$admin_pass_set" == false ]
do
    while test "$admintoken1" == ""
    do
        read -rp "Set PCCS server administrator password (plain text): " admintoken1
    done
    
    if [[ "${PCCS_SKIP_CRACKLIB:-0}" == "1" ]]; then
        echo -e "${YELLOW}PCCS_SKIP_CRACKLIB=1: skipping password strength checks for administrator.${NC}"
    elif ! pccs_check_password_strength "$admintoken1"; then
        if [ "$cracklib_limit" -gt 0 ]; then
            echo -e "${RED}The password does not meet requirements. Please try again ($cracklib_limit attempts left).${NC}"
            echo "You entered (${#admintoken1} chars): ${admintoken1}"
            admintoken1=""
            cracklib_limit=$(( "$cracklib_limit" - 1 ))
            continue
        else
            echo "Installation aborted. Please try again."
            exit 1
        fi
    fi

    while test "$admintoken2" == ""
    do
        read -rp "Re-enter administrator password (plain text): " admintoken2
    done

    if test "$admintoken1" != "$admintoken2"
    then
        echo "Passwords don't match."
        admintoken1=""
        admintoken2=""
        cracklib_limit=4
    else
        HASH="$(echo -n "$admintoken1" | sha512sum | tr -d '[:space:]-')"
        sed "/\"AdminTokenHash\"*/c\ \ \ \ \"AdminTokenHash\" \: \"${HASH}\"," -i ${configFile}
        admin_pass_set=true
    fi
done

#Ask for user password
cracklib_limit=4
usertoken1=""
usertoken2=""
user_pass_set=false
while [ "$user_pass_set" == false ]
do
    while test "$usertoken1" == ""
    do
        read -rp "Set PCCS server user password (plain text): " usertoken1
    done

    if [[ "${PCCS_SKIP_CRACKLIB:-0}" == "1" ]]; then
        echo -e "${YELLOW}PCCS_SKIP_CRACKLIB=1: skipping password strength checks for user.${NC}"
    elif ! pccs_check_password_strength "$usertoken1"; then
        if [ "$cracklib_limit" -gt 0 ]; then
            echo -e "${RED}The password does not meet requirements. Please try again ($cracklib_limit attempts left).${NC}"
            echo "You entered (${#usertoken1} chars): ${usertoken1}"
            usertoken1=""
            cracklib_limit=$(( "$cracklib_limit" - 1 ))
            continue
        else
            echo "Installation aborted. Please try again."
            exit 1
        fi
    fi

    while test "$usertoken2" == ""
    do
        read -rp "Re-enter user password (plain text): " usertoken2
    done

    if test "$usertoken1" != "$usertoken2"
    then
        echo "Passwords don't match."
        usertoken1=""
        usertoken2=""
        cracklib_limit=4
    else
        HASH="$(echo -n "$usertoken1" | sha512sum | tr -d '[:space:]-')"
        sed "/\"UserTokenHash\"*/c\ \ \ \ \"UserTokenHash\" \: \"${HASH}\"," -i ${configFile}
        user_pass_set=true
    fi
done

if which openssl > /dev/null 
then 
    genkey=""
    while [ "$genkey" == "" ]
    do
        read -rp "Do you want to generate insecure HTTPS key and cert for PCCS service? [Y] (Y/N) :" genkey 
        if [[ -z "$genkey" ||  "$genkey" == "Y" || "$genkey" == "y" ]] 
        then
            if [ ! -d ssl_key  ];then
                mkdir ssl_key
            fi
            openssl genrsa -out ssl_key/private.pem 2048
            openssl req -new -key ssl_key/private.pem -out ssl_key/csr.pem
            openssl x509 -req -days 365 -in ssl_key/csr.pem -signkey ssl_key/private.pem -out ssl_key/file.crt
            break
        elif [[ "$genkey" == "N" || "$genkey" == "n" ]] 
        then
            break
        else
            genkey=""
        fi
    done
else
    echo -e "${YELLOW}You need to setup HTTPS key and cert for PCCS to work. For how-to please check README. ${NC} "
fi

