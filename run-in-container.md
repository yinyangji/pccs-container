## 可以，AESMD 也能跑在容器里

这是 SGX 容器化的常见方案，Intel 官方也支持这种部署方式。

---

### 运行条件

AESMD 需要直接访问 SGX 设备，必须映射：

```bash
docker run -d \
  --name aesmd \
  --device /dev/sgx_enclave \
  --device /dev/sgx_provision \
  -v /var/run/aesmd:/var/run/aesmd \   # ← 把 socket 暴露给宿主机/其他容器
  intel/aesmd:latest
```

---

### 整体架构（全容器化）

```
宿主机
├── /dev/sgx_enclave        ← 硬件设备（必须存在）
├── /dev/sgx_provision      ← 硬件设备（必须存在）
└── /var/run/aesmd/         ← socket 目录（共享给各容器）

容器1: aesmd
├── 映射 /dev/sgx_enclave
├── 映射 /dev/sgx_provision
└── 输出 /var/run/aesmd/aesm.socket

容器2: PCKIDRetrievalTool / PCCS
└── 挂载 /var/run/aesmd     ← 通过 socket 调用 aesmd
```

**宿主机只需要有 SGX 驱动（内核模块），不需要安装任何 SGX 用户态服务。**

---

### docker-compose 完整示例

```yaml
version: '3.8'

services:
  # AESMD 服务
  aesmd:
    image: intel/intel-sgx:aesmd   # 或自己构建
    devices:
      - /dev/sgx_enclave:/dev/sgx_enclave
      - /dev/sgx_provision:/dev/sgx_provision
    volumes:
      - aesmd-socket:/var/run/aesmd   # 共享 socket
    restart: always

  # PCK 证书获取工具
  pck-retrieval:
    image: your-tools-image
    depends_on:
      - aesmd
    devices:
      - /dev/sgx_enclave:/dev/sgx_enclave
      - /dev/sgx_provision:/dev/sgx_provision
    volumes:
      - aesmd-socket:/var/run/aesmd   # 复用同一个 socket
      - ./output:/output
    command: >
      PCKIDRetrievalTool 
      -f /output/pckid_retrieval.csv
      -url https://pccs-host:8081
      -user_token your_token

  # PCCS 缓存服务
  pccs:
    image: your-pccs-image
    volumes:
      - aesmd-socket:/var/run/aesmd
      - ./pccs-config:/opt/intel/pccs/config
    ports:
      - "8081:8081"

volumes:
  aesmd-socket:   # 命名 volume 共享 socket 目录
```

---

### 自己构建 AESMD 镜像（如果没有现成镜像）

```dockerfile
FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    gnupg wget

# 添加 Intel SGX 仓库
RUN wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key \
    | apt-key add - && \
    echo "deb https://download.01.org/intel-sgx/sgx_repo/ubuntu focal main" \
    > /etc/apt/sources.list.d/intel-sgx.list

# 只安装用户态组件（不装驱动）
RUN apt-get update && apt-get install -y \
    libsgx-enclave-common \
    libsgx-aesm-service \
    sgx-aesm-service

# 创建 socket 目录
RUN mkdir -p /var/run/aesmd

CMD ["/opt/intel/sgx-aesm-service/aesm/aesm_service", "--no-daemon"]
```

---

### 关键注意事项

| 注意点 | 说明 |
|---|---|
| **驱动必须在宿主机** | 内核模块 `intel_sgx` 无法容器化，`lsmod \| grep sgx` 确认 |
| **socket 共享方式** | 推荐用命名 volume，比 bind mount 更干净 |
| **只启动一个 AESMD** | 多个 AESMD 实例会冲突，整个集群只跑一个 |
| **设备权限** | 容器用户需要有 `/dev/sgx_provision` 读权限，必要时加 `--group-add` |

---

### 宿主机最小要求

```bash
# 只需要确认驱动加载了
lsmod | grep sgx
# 输出类似：intel_sgx   xxx   0

# 设备节点存在
ls /dev/sgx*
```

**宿主机不需要安装 aesmd、不需要 libsgx 任何包**，全部在容器里跑即可。这也是 SGX 云原生部署的标准做法。