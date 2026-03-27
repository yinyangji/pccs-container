# SGX PCCS Container（Ubuntu 24.04，Rootless Podman）

## 1) 前置条件

- 主机已安装 `podman`（支持 rootless）
- 主机已配置 SGX 设备节点（如 `/dev/sgx_enclave`、`/dev/sgx_provision`；EDMM 场景常需 `/dev/sgx_vepc`）
- 主机网络可访问 Intel PCS
- 已申请 **Intel PCS API Key**

## 2) 组件与来源

| 组件 | 说明 |
|------|------|
| **`aesm-service/`** | 来自 **Intel® Software Guard Extensions** 官方 Linux 发行配套思路下的 Docker 多阶段示例（目录内 `Dockerfile`、`build_and_run_aesm_docker.sh` 含 **Intel 版权声明**，由 **intel/linux-sgx** 一类上游材料复制/改编而来）。本仓库用其 **`aesm` 构建目标** 生成 AESM 服务镜像，在容器内运行 `aesm_service --no-daemon`，并将 **`aesm.socket` 落在宿主机目录**（默认 **`~/aesmd-shared`**，与 PCCS 共用绑定挂载），以便 **host 上普通用户进程** 连接 AESM。 |
| **本仓库 `Dockerfile` / `build-image.sh`** | 构建 PCCS **运行环境镜像**（Intel SGX APT 源、依赖与入口脚本；PCCS 包 **`sgx-dcap-pccs`** 默认在容器内按需安装，见下文）。 |
| **`run-pccs-rootless.sh`** | 以 rootless Podman 启动 PCCS 容器，挂载 AESM socket 宿主机目录、SGX 设备与项目目录。 |

架构要点：**先起 AESMD 容器**，再起 PCCS；两者通过**同一宿主机目录**（默认 **`$HOME/aesmd-shared`**，环境变量 **`AESMD_SOCKET_DIR`**）绑定到容器内 **`/var/run/aesmd`**，PCCS 与 host 进程均使用其中的 **`aesm.socket`**。

## 3) 配置 rootless Podman 镜像加速（可选）

以下配置仅作用于当前用户，不影响系统全局：

```bash
mkdir -p ~/.config/containers
cat > ~/.config/containers/registries.conf <<'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "docker.1ms.run"

[[registry]]
prefix = "registry-1.docker.io"
location = "docker.1ms.run"
EOF
```

验证：

```bash
podman info | sed -n '/registries:/,/store:/p'
podman pull ubuntu:24.04
```

回退：

```bash
mv ~/.config/containers/registries.conf ~/.config/containers/registries.conf.bak
```

## 4) 构建 PCCS 基础镜像

在仓库根目录：

```bash
./build-image.sh
```

构建默认使用主机网络（等价于 `podman build --network host`）。可选：

```bash
BUILD_NETWORK=host ./build-image.sh
./build-image.sh --no-cache
```

代理：仅当传入 `./build-image.sh --proxy=ip:port` 时，构建过程才会使用代理；**最终镜像不会**写入代理环境变量。

默认基础镜像会先尝试 `docker.1ms.run/library/ubuntu:24.04`，失败则回退 `ubuntu:24.04`。`APT_MIRROR=aliyun`（默认）在构建阶段将 Ubuntu 源切到阿里云；`APT_MIRROR=official` 使用上游。

参考：[Intel TDX Enabling Guide — PCCS](https://cc-enabling.trustedservices.intel.com/intel-tdx-enabling-guide/02/infrastructure_setup/#provisioning-certificate-caching-service-pccs)

可选：

```bash
IMAGE_NAME="localhost/local/sgx-pccs-aesmd:ubuntu24.04" ./build-image.sh
BASE_IMAGES="docker.1ms.run/library/ubuntu:24.04,ubuntu:24.04" ./build-image.sh
```

## 5) Podman rootless 端到端：AESMD + PCCS

### 5.1 启动 AESMD（`aesm-service`）

在仓库根目录执行（将 `podman` 对应替换为你环境中的命令即可；与 Intel 原版 `build_and_run_aesm_docker.sh` 中的 `docker` 命令等价）：

```bash
cd aesm-service
podman build --target aesm -t localhost/sgx_aesm -f ./Dockerfile ./
```

创建与 PCCS 脚本一致的 **宿主机 socket 目录**（默认 **`~/aesmd-shared`**，脚本会设置组与 ACL，便于 host 普通用户访问）：

```bash
mkdir -p ~/aesmd-shared
```

推荐直接使用脚本（含构建、权限与 `podman run` 参数）：

```bash
./build_and_run_aesm_docker.sh
```

或手动启动 AESM 容器（按主机设备情况增减 `--device`；无 `/dev/sgx_vepc` 则去掉该行）：

```bash
podman rm -f aesm-service 2>/dev/null || true
podman run -d --name aesm-service --privileged --security-opt label=disable \
  --device /dev/sgx_enclave --device /dev/sgx_provision \
  $([ -e /dev/sgx_vepc ] && echo --device /dev/sgx_vepc) \
  -v "${HOME}/aesmd-shared:/var/run/aesmd:Z" \
  localhost/sgx_aesm
```

确认 socket 侧就绪（主机上应能看到 **`~/aesmd-shared/aesm.socket`**，或使用 `podman exec`）：

```bash
podman ps --filter name=aesm-service
podman logs aesm-service
```

### 5.2 启动 PCCS 容器（首次建议手动安装模式）

默认 **`PCCS_MANUAL_INSTALL_MODE=true`**：容器起后台空闲进程，便于你 **`podman exec` 进容器** 安装 PCCS 包并完成 Intel 的 `install.sh`。请设置 API Key 等信息：

```bash
cd /path/to/pccs-container
PCCS_API_KEY="<你的_Intel_PCS_API_KEY>" ./run-pccs-rootless.sh
```

常用可选环境变量：`PCCS_PORT`、`CONTAINER_NAME`、`AESMD_SOCKET_VOLUME`、`PROJECTS_HOST_DIR`、`NETWORK_MODE` 等（见文末「环境变量说明」）。

进入容器：

```bash
podman exec -it sgx-pccs bash
```

### 5.3 容器内安装 `sgx-dcap-pccs` 并完成配置

镜像已配置 Intel SGX APT 源与占位 **`/usr/bin/systemctl`** / **`initctl`**（供 `dpkg` 在无 systemd 环境下通过维护脚本）。**Podman** 下 cgroup 通常不含 `docker` 字符串，Intel `startup.sh` 会误判环境；因此 **`apt` 完成配置前** 需要存在 **`/run/systemd/system`**（`/run` 多为 tmpfs，**新起容器后**若再次安装需重做）：

```bash
sudo install -d /run/systemd/system
# 或（重建镜像后可用）: sudo /usr/local/bin/pccs-apt-prep.sh
sudo apt-get update
sudo apt-get install -y sgx-dcap-pccs
```

若包已解压但 **`dpkg --configure` 曾失败**，可：

```bash
sudo install -d /run/systemd/system
sudo dpkg --configure -a
```

若仍提示找不到 `systemctl`，确认占位在 **`/usr/bin`**（勿仅用 `/usr/local/bin`，因 `dpkg` 的 `PATH` 常不含后者）：

```bash
for n in systemctl initctl; do printf '%s\n' '#!/bin/sh' 'exit 0' | sudo tee "/usr/bin/$n" >/dev/null; sudo chmod 755 "/usr/bin/$n"; done
sudo dpkg --configure -a
```

非交互安装时 Intel 会跳过由 **`pccs` 用户** 运行的 **`install.sh`**。在容器内执行（与包内提示一致）：

```bash
/bin/su - pccs -c '/opt/intel/sgx-dcap-pccs/install.sh'
```

安装完成后应存在 **`/opt/intel/sgx-dcap-pccs`** 及配置模板；本仓库入口脚本会用环境变量渲染 **`config/default.json`**。

### 5.4 改为由入口脚本自动运行 PCCS

确认 AESMD 仍在运行且 **`~/aesmd-shared`**（或你配置的 **`AESMD_SOCKET_DIR`**）仍存在。在宿主机：

```bash
PCCS_MANUAL_INSTALL_MODE=false PCCS_API_KEY="<你的_Intel_PCS_API_KEY>" ./run-pccs-rootless.sh
```

之后 PCCS 由镜像入口 **`pccs-entrypoint.sh`** 启动 `node pccs_server.js`。调试时可设 `PCCS_DEBUG_SHELL_ON_FAIL=true`（默认），失败时留在 shell。

自定义端口与容器名示例：

```bash
PCCS_MANUAL_INSTALL_MODE=false \
PCCS_API_KEY="<你的_Intel_PCS_API_KEY>" \
PCCS_PORT=8081 \
CONTAINER_NAME="sgx-pccs" \
./run-pccs-rootless.sh
```

### 5.5 设备映射、AESM socket 与权限

- **设备**：`run-pccs-rootless.sh` 映射 `/dev/sgx_enclave`、`/dev/sgx_provision`；若主机存在 **`/dev/sgx_vepc`** 则一并映射（QE3/EDMM 常见依赖）。
- **Rootless**：打开设备仍受宿主机内核与节点权限约束。通常需将运行 Podman 的用户加入 **`sgx`** 组（`sudo usermod -aG sgx "$USER"` 后重新登录或 `newgrp sgx`）。若 `/dev/sgx_provision` 为 `root:root` 且 `600`，需按安全策略调整 udev/组或改用有权限的方式运行。
- **脚本**：已使用 **`--group-add keep-groups`** 以继承宿主辅助组。
- **AESM socket 目录**：默认 **`$HOME/aesmd-shared`** 绑定到容器内 **`/var/run/aesmd`**（**`aesm.socket`**）。覆盖时使用 **`AESMD_SOCKET_DIR`**（须与 AESM、PCCS 一致）。
- **镜像内 sudo**：已配置免密 sudo，便于在 `podman exec` 内安装与排查。

## 6) 容器内代理与排错（apt / pip）

### apt 代理（仅安装依赖时需要）

临时：

```bash
sudo apt-get update -o Acquire::http::Proxy=http://127.0.0.1:7890 -o Acquire::https::Proxy=http://127.0.0.1:7890
```

持久（示例）：

```bash
sudo tee /etc/apt/apt.conf.d/99proxy >/dev/null <<'EOF'
Acquire::http::Proxy "http://127.0.0.1:7890";
Acquire::https::Proxy "http://127.0.0.1:7890";
EOF
```

取消：`sudo rm -f /etc/apt/apt.conf.d/99proxy`。

`wget`/`curl` 等可另设 `http_proxy`/`https_proxy` 环境变量。

### `sgx-dcap-pccs` 与 `systemctl` / Podman（小结）

- 占位 **`systemctl`** 须在 **`/usr/bin`**；且 **`/run/systemd/system`** 须在 **`dpkg --configure` 前** 创建（见 **§5.3**）。**Podman** 下 cgroup 不含 `docker` 时，仅依赖「容器检测」分支不可靠，**务必**创建该目录。
- 镜像构建请使用当前仓库 **`Dockerfile`**，以包含上述占位与 **`pccs-apt-prep.sh`**。

### pip 代理（部分 Intel 脚本会在 post-install 调用 pip）

```bash
sudo tee /etc/pip.conf >/dev/null <<'EOF'
[global]
proxy = http://127.0.0.1:7890
EOF
sudo dpkg --configure -a
sudo apt-get -f install
```

## 7) 运行状态检查

```bash
podman ps --filter name=aesm-service
podman ps --filter name=sgx-pccs
podman logs -f aesm-service
podman logs -f sgx-pccs
```

## 8) 停止与删除

```bash
podman rm -f sgx-pccs
podman rm -f aesm-service
# 若需清空 socket：rm -f ~/aesmd-shared/aesm.socket（并视情况重启 AESM 容器）
```

## 9) systemd user unit（可选）

模板在仓库 **`systemd/user/`**（已修复 `ExecStartPre`，避免出现 journal 里 **`socket_dir` 未设置**、**`AESMD_SOCKET_DIR///.../$HOME`** 等误报）。

```bash
./install-user-unit.sh install   # 复制单元到 ~/.config/systemd/user/，必要时修正异常的 AESMD_SOCKET_DIR 行
./install-user-unit.sh remove    # 停止并删除单元，避免与手动 podman 抢容器名
```

默认不 `enable --now`；需要自启时再执行 `systemctl --user enable --now sgx-aesm.service`。日常也可只用 **`aesm-service/build_and_run_aesm_docker.sh`** 与 **`pccs/build_and_run_pccs_docker.sh`**。

## 环境变量说明（常用）

- `PCCS_API_KEY`：Intel PCS API Key（建议必填）
- `PCCS_PORT`：监听端口（默认 `8081`；非 host 网络时需自行 `-p` 映射）
- `PCCS_MANUAL_INSTALL_MODE`：首次安装 `true`，完成后改为 `false`（默认脚本为 `true`）
- `AESMD_SOCKET_DIR`：与 AESMD 共用的**宿主机目录**（默认 `$HOME/aesmd-shared`）
- `PROJECTS_HOST_DIR` / `PROJECTS_CONTAINER_DIR`：宿主机项目目录映射进 PCCS 容器
- `PCCS_ADMIN_PASSWORD` / `PCCS_USER_PASSWORD` / `PCCS_PROXY` / `PCCS_REFRESH_SCHEDULE` / `PCCS_LOG_LEVEL` / `PCCS_USE_SECURE_CERT`
- `PCCS_DEBUG_SHELL_ON_FAIL`：PCCS 退出后是否进入 shell 便于排查

## 无 sudo 网络体检（排查“联不上网”）

```bash
chmod +x ./network-check-nosudo.sh
./network-check-nosudo.sh
```

脚本检查路由、DNS、TCP 80/443、`curl` 等，全程不需要 `sudo`。
