## Rootless 双容器运行说明（AESMD + PCCS）

**完整步骤（含 AESM 镜像来源、`sgx-dcap-pccs` 安装与 Podman 命令）已写入仓库根目录 [`README.md`](./README.md)。** 下文为简要索引，可能与脚本细节不完全同步。

本文档与当前脚本保持一致：

- `run-aesm-rootless.sh`：只启动 `aesmd` 容器
- `run-pccs-rootless.sh`：只启动 `pccs` 容器
- 两者通过宿主机目录共享 `aesm.socket`

---

### 1) 架构与依赖

```text
宿主机
├── /dev/sgx_enclave
├── /dev/sgx_provision
└── ${HOME}/.local/share/aesmd-shared/aesm.socket
     ^ 由 aesmd 容器创建

容器 A: aesmd
└── 输出 /var/run/aesmd/aesm.socket

容器 B: pccs
└── 挂载 /var/run/aesmd，连接 aesm.socket
```

关键点：

- 只启动一个 `aesmd` 实例
- 先启动 `aesmd`，再启动 `pccs`
- `pccs` 侧不再自行启动 `aesmd`

---

### 2) 启动前检查（宿主机）

```bash
ls /dev/sgx_enclave /dev/sgx_provision
```

若缺失，先完成宿主机 SGX 驱动/设备配置。

---

### 3) 启动 AESMD 容器

```bash
cd /home/chenpengyu/projects/pccs-container
./run-aesm-rootless.sh
```

可选环境变量：

```bash
IMAGE_NAME=ghcr.io/oasisprotocol/aesmd-dcap:master
CONTAINER_NAME=aesmd
RESTART_POLICY=always
AESMD_SOCKET_DIR="${HOME}/.local/share/aesmd-shared"
```

脚本会检查：

- 镜像是否存在
- SGX 设备是否存在
- `aesm.socket` 是否就绪

---

### 4) 启动 PCCS 容器

```bash
cd /home/chenpengyu/projects/pccs-container
PCCS_API_KEY="<your_intel_pcs_api_key>" ./run-pccs-rootless.sh
```

可选环境变量：

```bash
IMAGE_NAME=localhost/local/sgx-pccs-aesmd:ubuntu24.04
CONTAINER_NAME=sgx-pccs
PCCS_PORT=8081
PCCS_HOST=0.0.0.0
PCCS_ADMIN_PASSWORD='PccsAdmin!234'
PCCS_USER_PASSWORD='PccsUser!234'
PCCS_PROXY=''
PCCS_REFRESH_SCHEDULE='0 */12 * * *'
PCCS_LOG_LEVEL=info
PCCS_USE_SECURE_CERT=false
AESMD_SOCKET_DIR="${HOME}/.local/share/aesmd-shared"
NETWORK_MODE=host
RESTART_POLICY=always
```

`run-pccs-rootless.sh` 会在启动前强校验：

- `AESMD_SOCKET_DIR` 存在
- `aesm.socket` 已存在（即 AESMD 已就绪）

---

### 5) 常用排查命令

```bash
podman ps --filter name=aesmd
podman ps --filter name=sgx-pccs

podman logs -f aesmd
podman logs -f sgx-pccs

ls -l "${HOME}/.local/share/aesmd-shared"
```

如 `pccs` 报错无法连接 AESM，优先检查：

1. `aesm.socket` 是否存在
2. `AESMD_SOCKET_DIR` 在两个脚本中是否一致
3. 容器是否都正常运行

---

### 6) 宿主机上跑 SGX 样例：把 AESM 连到用户目录下的 `aesm.socket`

Intel PSW 默认连 **`/var/run/aesmd/aesm.socket`**。用 `aesm-service/build_and_run_aesm_docker.sh` 时，socket 实际在 **`$AESMD_SOCKET_DIR/aesm.socket`**（默认 **`$HOME/aesmd-shared/aesm.socket`**），未做 root 下符号链接时，宿主机上的 **`app`** 会报：

`Failed to connect to socket /var/run/aesmd/aesm.socket`

可用仓库 **`aesm-service/redirect_sock.c`**：编译为共享库，**`LD_PRELOAD`** 在进程内把对上述固定路径的 `connect` 重定向到你的用户路径。

```bash
cd "${HOME}/projects/pccs-container/aesm-service"
gcc -fPIC -shared -o libredirect.so redirect_sock.c -ldl
```

运行样例（路径与 **`AESMD_SOCKET_DIR`** 一致；下面以默认 **`~/aesmd-shared`** 为例）：

```bash
export AESMD_SOCKET_REDIRECT="${HOME}/aesmd-shared/aesm.socket"
export LD_PRELOAD=/绝对路径/到/libredirect.so
# 若样例依赖 sample 自带 libcrypto：
LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${PWD}/sample_libcrypto" ./app
```

一行示例（在样例目录下、且已 `export AESMD_SOCKET_REDIRECT`）：

```bash
AESMD_SOCKET_REDIRECT="${HOME}/aesmd-shared/aesm.socket" \
  LD_PRELOAD="${HOME}/projects/pccs-container/aesm-service/libredirect.so" \
  LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${PWD}/sample_libcrypto" \
  ./app
```

说明：

- **`AESMD_SOCKET_REDIRECT`**：重定向目标，须为**实际存在的** socket 路径（先确保 AESM 容器已启动且 `ls -l` 可见该文件）。
- **`LD_PRELOAD`**：请使用 **`libredirect.so` 的绝对路径**，避免工作目录变化后找不到库。
- 仅影响**当前进程**及其子进程；不修改系统全局配置。