#!/bin/bash
set -e

# ThorCraft: pin every target to an explicit tag and let a failed clone fail the
# build. Upstream ended each clone with "|| true", so a network or tag error
# left an empty tree and the failure only surfaced much later as a confusing
# build error. JDK_TAG overrides the pin for A/B runs.
#
# aarch64 was held at 8u482-ga because JDK-8360869 (in 8u502) rejects the NDK
# clang as "GCC < 5"; patches/jdk8u_aarch64_gcc4_check.diff narrows that guard
# to real GCC, so the pin can move forward.

if [[ "$TARGET_JDK" == "arm" ]]; then
  git clone --depth 1 https://github.com/openjdk/aarch32-port-jdk8u openjdk
elif [[ "$BUILD_IOS" == "1" ]]; then
  git clone --depth 1 https://github.com/corretto/corretto-8 --branch 8.472.08.1 openjdk
else
  git clone --depth 1 https://github.com/openjdk/jdk8u --branch "${JDK_TAG:-jdk8u502-ga}" openjdk
fi
