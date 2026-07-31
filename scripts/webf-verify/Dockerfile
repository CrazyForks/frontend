# syntax=docker/dockerfile:1
# WebF 验证容器（songloft-org/songloft#341）
#
# 为什么需要它：开发机是 Ubuntu 22.04（glibc 2.35），而 WebF 预编译的
# linux/libwebf.so 需要 glibc >= 2.38（版本需求表里有 fmod@GLIBC_2.38 /
# __isoc23_strtol@GLIBC_2.38）。Debian bookworm 是 2.36，同样不够，
# 所以基础镜像必须是 Ubuntu 24.04（glibc 2.39）。
# 开发机同时缺 clang++/ninja（flutter build linux 过不去）、无 Android SDK、
# 无 Xcode/Windows，唯一可用目标是 Chrome(web) —— 恰是 WebF 不支持的平台。
#
# 用法见同目录 run.sh。

FROM ubuntu:24.04

ARG FLUTTER_VERSION=3.44.6

ENV DEBIAN_FRONTEND=noninteractive

# 1. 工具链
#    - clang/cmake/ninja/pkg-config/libgtk-3-dev：Flutter Linux 桌面
#    - nodejs：WebF 的 linux/CMakeLists.txt 会调 resolve_libs.js 拷共享库，
#      缺 node 只 warn 后退化成符号链接（容易在运行期才炸）
#    - xvfb/imagemagick/x11-utils：无头跑 GUI + 抓屏
#    - mesa 软渲染：Xvfb 下没有 GPU，Flutter 的 GL 后端要靠 llvmpipe
RUN apt-get update -y && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip \
      clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-13-dev \
      nodejs \
      xvfb x11-utils imagemagick \
      libgl1-mesa-dri libglu1-mesa mesa-utils libegl1 \
      python3 python3-fonttools \
    && rm -rf /var/lib/apt/lists/*

# 2. Flutter SDK（版本对齐 CI 的 FLUTTER_VERSION=3.44.6）
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN git clone https://github.com/flutter/flutter.git -b ${FLUTTER_VERSION} --depth 1 ${FLUTTER_HOME} \
    && git config --global --add safe.directory ${FLUTTER_HOME} \
    && flutter config --no-analytics \
    && flutter precache --linux \
    && flutter doctor -v

# 3. 探针 app 骨架 + webf 依赖（在镜像里预热，避免每次 run 都拉 28.5 MB 包）
ENV PROBE_HOME=/opt/webf_probe
RUN flutter create --platforms=linux --project-name webf_probe ${PROBE_HOME}

COPY probe_pubspec.yaml ${PROBE_HOME}/pubspec.yaml
RUN cd ${PROBE_HOME} && flutter pub get

COPY probe_main.dart ${PROBE_HOME}/lib/main.dart
COPY probe.html /opt/probe.html
COPY probe-after.css /opt/probe-after.css
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 预编译一次，把 CMake 配置与 WebF 的共享库拷贝固化进镜像，
# 让每次 run 只跑增量构建
RUN cd ${PROBE_HOME} && flutter build linux --release

WORKDIR ${PROBE_HOME}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
