#!/bin/bash
set -e

# ThorCraft: pin to an explicit GA tag. Upstream cloned jdk25u's default branch,
# so the patch level silently changed between runs and could not be reproduced.
# JDK_TAG overrides the pin for A/B runs.

git clone --branch "${JDK_TAG:-jdk-25.0.4-ga}" --depth 1 \
  https://github.com/openjdk/jdk25u openjdk
