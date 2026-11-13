#!/bin/sh
# The packages CI needs, on Ubuntu 22.04: the board's release, so the same Qt 6.2.4 (step 1.1). Installs them on
# GitHub's runner (.github/workflows/ci.yml) and in the local Docker image (scripts/in-docker.sh). Run as root.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
    ca-certificates cmake ninja-build g++ git \
    qt6-base-dev libqt6opengl6-dev qt6-declarative-dev qt6-declarative-dev-tools \
    qml6-module-qtquick qml6-module-qtquick-window qml6-module-qtqml-workerscript qml6-module-qttest \
    libgl-dev libegl-dev libgles-dev libdrm-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    clang-format \
    device-tree-compiler
