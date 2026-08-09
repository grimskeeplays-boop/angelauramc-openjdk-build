#!/bin/bash
set -e

# ThorCraft: pin every line to an explicit GA tag. Upstream cloned jdk17u's
# default branch, which meant the JDK patch level silently changed between
# runs and could not be reproduced. JDK_TAG overrides the pin for A/B runs.

if [[ $TARGET_VERSION -eq 21 ]]; then
    tag="${JDK_TAG:-jdk-21.0.12-ga}"
    git clone --branch "$tag" --depth 1 https://github.com/openjdk/jdk21u openjdk-21
else
    tag="${JDK_TAG:-jdk-17.0.20-ga}"
    git clone --branch "$tag" --depth 1 https://github.com/openjdk/jdk17u openjdk-17
fi
