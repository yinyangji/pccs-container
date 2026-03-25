#!/bin/sh
# Prepare runtime for `apt install sgx-dcap-pccs` inside OCI containers.
# Intel startup.sh uses /run/systemd/system to decide whether to call systemctl.
# Podman cgroup paths usually do not contain "docker", so without this directory
# the installer exits with status 5. /run is often tmpfs — re-run after container restart.
set -e
install -d /run/systemd/system
echo "OK: /run/systemd/system is ready (re-run this after container restart if apt configure fails)."
