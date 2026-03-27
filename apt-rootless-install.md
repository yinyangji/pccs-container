# APT Rootless 安装指南（无 sudo）

本文档用于以下场景：
- 你在 **host 没有 sudo**，但希望使用本地 SGX repo 下载包
- 你在 **rootless 容器**里有 sudo（或容器内 root），希望安装 SGX 包

本地仓库示例路径：
- `/home/chenpengyu/tools/sgx_debian_local_repo`

---

## 1. 结论先说

- **host 无 sudo**：不能执行系统级 `apt update`/`apt install`（会写 `/var/lib/apt`、`/etc/apt`）。
- 但可以用 **用户态 apt 工作目录** 实现：
  - `apt-get update`（写到 `$HOME/.apt-user`）
  - `apt-get download` 下载 `.deb`
- 真实“安装到系统”仍需 root（sudo）。
- 若无 sudo，可将 `.deb` 解包到用户目录并用 `LD_LIBRARY_PATH` 运行。

---

## 2. 用户态 apt（rootless）配置本地 repo

### 2.1 准备目录

```bash
mkdir -p "$HOME/.apt-user/etc/keyrings" \
         "$HOME/.apt-user/state/lists/partial" \
         "$HOME/.apt-user/cache/archives/partial"
```

### 2.2 导入 repo key（推荐）

```bash
gpg --dearmor \
  -o "$HOME/.apt-user/etc/keyrings/intel-sgx-local.gpg" \
  "/home/chenpengyu/tools/sgx_debian_local_repo/keys/intel-sgx.key"
```

### 2.3 写 source（signed-by）

```bash
cat > "$HOME/.apt-user/etc/sources.list" <<EOF
deb [arch=amd64 signed-by=$HOME/.apt-user/etc/keyrings/intel-sgx-local.gpg] file:/home/chenpengyu/tools/sgx_debian_local_repo noble main
EOF
```

### 2.4 rootless update（不会写系统目录）

```bash
apt-get \
  -o Dir::Etc::sourcelist="$HOME/.apt-user/etc/sources.list" \
  -o Dir::Etc::sourceparts="-" \
  -o APT::Get::List-Cleanup="0" \
  -o Dir::State="$HOME/.apt-user/state" \
  -o Dir::Cache="$HOME/.apt-user/cache" \
  update
```

---

## 3. rootless 下载 `.deb`（不安装）

```bash
apt-get \
  -o Dir::Etc::sourcelist="$HOME/.apt-user/etc/sources.list" \
  -o Dir::Etc::sourceparts="-" \
  -o APT::Get::List-Cleanup="0" \
  -o Dir::State="$HOME/.apt-user/state" \
  -o Dir::Cache="$HOME/.apt-user/cache" \
  download \
  libsgx-qe3-logic \
  libsgx-quote-ex \
  libsgx-dcap-ql \
  libsgx-dcap-default-qpl
```

> 注意：你当前本地 repo 中不一定包含 `libsgx-epid`，若报 `Unable to locate package`，通常是 repo 本身没有该包，不是权限问题。

---

## 3.1 命令简化：定义 `sgx_apt` 函数（推荐）

每次都写一长串 `-o Dir::...` 很麻烦，建议在 `~/.bashrc` 里加一个函数：

```bash
sgx_apt() {
  apt-get \
    -o Dir::Etc::sourcelist="$HOME/.apt-user/etc/sources.list" \
    -o Dir::Etc::sourceparts="-" \
    -o APT::Get::List-Cleanup="0" \
    -o Dir::State="$HOME/.apt-user/state" \
    -o Dir::Cache="$HOME/.apt-user/cache" \
    "$@"
}
```

使其生效：

```bash
source ~/.bashrc
```

之后就可以直接：

```bash
sgx_apt update
sgx_apt download libsgx-urts libsgx-qe3-logic libsgx-quote-ex libsgx-dcap-ql libsgx-dcap-default-qpl
```

可选再加一个短别名：

```bash
alias sapt='sgx_apt'
```

然后使用：

```bash
sapt update
sapt download libsgx-urts
```

---

## 4. 批量安装 `.deb`（有 sudo 的环境）

在容器内（有免密 sudo）或 host 有 sudo 时：

```bash
sudo dpkg -i ./*.deb || sudo apt-get -f install -y
```

---

## 5. host 无 sudo：解包到 `~/opt/usr`（替代安装）

如果你无法 `apt install`，可把 `.deb` 解包到用户目录：

```bash
mkdir -p "$HOME/opt"
for f in ./*.deb; do
  dpkg-deb -x "$f" "$HOME/opt"
done
```

这会生成类似目录：

- `~/opt/usr/lib/x86_64-linux-gnu`
- `~/opt/usr/lib`
- `~/opt/usr/bin`

运行前建议设置用户态运行环境：

```bash
export PATH="$HOME/opt/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/opt/usr/lib/x86_64-linux-gnu:$HOME/opt/usr/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$HOME/opt/usr/lib/x86_64-linux-gnu/pkgconfig:$HOME/opt/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
```

可加到 `~/.bashrc` 持久化：

```bash
cat >> ~/.bashrc <<'EOF'
export PATH="$HOME/opt/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/opt/usr/lib/x86_64-linux-gnu:$HOME/opt/usr/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$HOME/opt/usr/lib/x86_64-linux-gnu/pkgconfig:$HOME/opt/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
EOF
source ~/.bashrc
```

可用以下命令快速验证库是否已落到用户目录：

```bash
ls "$HOME/opt/usr/lib/x86_64-linux-gnu" | grep -E 'sgx|dcap|quote|qe'
```

> 建议同一套包只保留一个版本（例如都用 `1.25/2.28`），避免混用 `1.23` 与 `1.25` 导致动态库冲突。

---

## 6. 常见报错与处理

- `Could not open lock file /var/lib/apt/lists/lock`
  - 你在 host 无 sudo，且用了系统 apt 路径。请改用本文第 2 节的用户态 apt 参数。

- `NO_PUBKEY E5C7F0FA1C6C6C3C`
  - key 未导入到 apt keyring，按第 2.2/2.3 节重新配置 `signed-by`。

- `Unable to locate package <name>`
  - 先检查本地 repo 的 `Packages` 是否包含该包；不包含时换包名或补齐仓库内容。

---

## 7. 最短命令速查

### 仅下载（无 sudo）

```bash
apt-get -o Dir::Etc::sourcelist="$HOME/.apt-user/etc/sources.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" -o Dir::State="$HOME/.apt-user/state" -o Dir::Cache="$HOME/.apt-user/cache" download libsgx-qe3-logic libsgx-quote-ex libsgx-dcap-ql libsgx-dcap-default-qpl
```

或使用函数简化版：

```bash
sgx_apt download libsgx-qe3-logic libsgx-quote-ex libsgx-dcap-ql libsgx-dcap-default-qpl
```

### 当前目录批量安装（有 sudo）

```bash
sudo dpkg -i ./*.deb || sudo apt-get -f install -y
```

