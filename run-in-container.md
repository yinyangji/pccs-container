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