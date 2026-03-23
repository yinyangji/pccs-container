# SGX PCCS Container (Ubuntu 24.04, Rootless Podman)

## 1) 前置条件

- 主机已安装 `podman`（支持 rootless）
- 主机网络可访问 Intel PCS
- 你已申请 Intel PCS API Key

## 2) 配置 rootless Podman 镜像加速（可选）

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

验证配置：

```bash
podman info | sed -n '/registries:/,/store:/p'
podman pull ubuntu:24.04
```

回退配置（恢复默认）：

```bash
mv ~/.config/containers/registries.conf ~/.config/containers/registries.conf.bak
```

## 3) 构建镜像

```bash
./build-image.sh
```

默认基础镜像源已设置为：

- `docker.1ms.run/library/ubuntu:24.04`
- 容器内 PCCS 安装方式：通过 Intel SGX APT 源安装 `sgx-dcap-pccs`（Ubuntu 24.04 / noble）
- 构建脚本会自动回退基础镜像源：先尝试 `docker.1ms.run`，失败后回退 `ubuntu:24.04`

参考文档（Intel TDX Enabling Guide, PCCS）：

- [Infrastructure Setup - Intel TDX Enabling Guide](https://cc-enabling.trustedservices.intel.com/intel-tdx-enabling-guide/02/infrastructure_setup/#provisioning-certificate-caching-service-pccs)

可选自定义镜像名：

```bash
IMAGE_NAME="local/sgx-pccs:ubuntu24.04" ./build-image.sh
```

可选自定义候选基础镜像（逗号分隔，按顺序尝试）：

```bash
BASE_IMAGES="docker.1ms.run/library/ubuntu:24.04,ubuntu:24.04" ./build-image.sh
```

## 4) 启动 PCCS（rootless）

最小启动：

```bash
PCCS_API_KEY="<你的Intel_PCS_API_KEY>" ./run-pccs-rootless.sh
```

自定义端口和容器名：

```bash
PCCS_API_KEY="<你的Intel_PCS_API_KEY>" \
PCCS_PORT=8081 \
CONTAINER_NAME="sgx-pccs" \
./run-pccs-rootless.sh
```

## 5) 运行状态检查

```bash
podman ps --filter name=sgx-pccs
podman logs -f sgx-pccs
```

## 6) 停止与删除

```bash
podman rm -f sgx-pccs
```

## 7) 作为 systemd user unit 运行（登录前可用）

安装并启动 user unit：

```bash
./install-user-unit.sh
```

安装脚本会生成：

- `~/.config/systemd/user/sgx-pccs.service`
- `~/.config/sgx-pccs/pccs.env`

编辑 `~/.config/sgx-pccs/pccs.env` 后重启服务：

```bash
systemctl --user restart sgx-pccs.service
```

查看服务状态与日志：

```bash
systemctl --user status sgx-pccs.service
journalctl --user -u sgx-pccs.service -f
```

要实现“所有用户登录前就可用”，必须启用 linger（仅需一次）：

```bash
sudo loginctl enable-linger $USER
loginctl show-user $USER -p Linger
```

`Linger=yes` 后，用户 systemd manager 会在开机时启动，`sgx-pccs.service` 将在用户未登录时自动拉起。

## 环境变量说明（常用）

- `PCCS_API_KEY`：Intel PCS API Key（建议必填）
- `PCCS_PORT`：主机映射端口（默认 `8081`）
- `PCCS_ADMIN_PASSWORD`：PCCS 管理口令
- `PCCS_USER_PASSWORD`：PCCS 用户口令
- `PCCS_PROXY`：代理地址（如 `http://proxy:port`）
- `PCCS_REFRESH_SCHEDULE`：刷新计划（cron 表达式）
- `PCCS_LOG_LEVEL`：日志级别（默认 `info`）
- `PCCS_USE_SECURE_CERT`：是否使用安全证书（`true/false`）

## 无 sudo 网络体检（排查“联不上网”）

执行一键体检脚本：

```bash
chmod +x ./network-check-nosudo.sh
./network-check-nosudo.sh
```

脚本会检查：

- 默认路由与网关可达性
- DNS 解析是否正常
- 到公网 IP 的 TCP 端口连通性（80/443）
- 基本 HTTP/HTTPS 连通性（`curl`）

并输出简要结论（如 DNS 故障、仅局域网可达、疑似出站被策略拦截等），全程不需要 `sudo`。
