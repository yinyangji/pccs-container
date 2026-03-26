# Deploy QGS service on Docker

QGS (Quote Generation Service) implementation comes from
[DCAP](https://github.com/intel/SGXDataCenterAttestationPrimitives/tree/master/QuoteGeneration/quote_wrapper/qgs).
Currently, the package of QGS only support several distros. Using docker to deploy the QGS service can be an alternative for some unsupported distros, like RHEL9.

本目录下 `./build_and_run_qgs_docker.sh` 默认**先构建镜像再启动容器**（与仓库 `aesm-service/build_and_run_aesm_docker.sh` 用法类似）。仅构建：`-a build`；仅启动已有镜像：`-a run`。

## 1. QGS Service Usage Guide

### 1.1 Start QGS Service

```bash
docker run -d --privileged --name qgs --restart always --net host <your registry>
```
- Check if QGS service works

```console
$ docker ps
CONTAINER ID   IMAGE      COMMAND                 CREATED         STATUS         PORTS      NAMES
90a3777d813e   qgs        "/opt/intel/tdx-qgs/…"  9 minutes ago   Up 9 minutes              qgs
```
