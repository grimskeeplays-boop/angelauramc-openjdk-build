#!/bin/bash
set -e
. setdevkitpath.sh

if [[ "$TARGET_JDK" == "arm" ]]
then
  export TARGET_JDK=aarch32
  export TARGET_PHYS=aarch32-linux-androideabi
  export JVM_VARIANTS=client
else
  export TARGET_PHYS=$TARGET
fi

export FREETYPE_DIR=$PWD/freetype-$BUILD_FREETYPE_VERSION/build_android-$TARGET_SHORT
export CUPS_DIR=$PWD/cups-2.2.4
export CFLAGS+=" -DLE_STANDALONE" # -I$FREETYPE_DIR -I$CUPS_DI

# if [[ "$TARGET_JDK" == "aarch32" ]] || [[ "$TARGET_JDK" == "aarch64" ]]
# then
#   export CFLAGS+=" -march=armv7-a+neon"
# fi

# It isn't good, but need make it build anyways
# cp -R $CUPS_DIR/* $ANDROID_INCLUDE/

# cp -R /usr/include/X11 $ANDROID_INCLUDE/
# cp -R /usr/include/fontconfig $ANDROID_INCLUDE/

if [[ "$BUILD_IOS" != "1" ]]; then
  export CFLAGS+=" -O3 -D__ANDROID__"

  ln -s -f /usr/include/X11 $ANDROID_INCLUDE/
  ln -s -f /usr/include/fontconfig $ANDROID_INCLUDE/
  AUTOCONF_x11arg="--x-includes=$ANDROID_INCLUDE/X11"

  export LDFLAGS+=" -L`pwd`/dummy_libs"

# Create dummy libraries so we won't have to remove them in OpenJDK makefiles
  mkdir -p dummy_libs
  ar cru dummy_libs/libpthread.a
  ar cru dummy_libs/libthread_db.a
else
  ln -s -f /opt/X11/include/X11 $ANDROID_INCLUDE/
  platform_args="--with-toolchain-type=clang SDKNAME=iphoneos"
  # --disable-precompiled-headers
  AUTOCONF_x11arg="--with-x=/opt/X11/include/X11 --prefix=/usr/lib"
  sameflags="-arch arm64 -DHEADLESS=1 -I$PWD/ios-missing-include -Wno-c++11-narrowing -Wno-implicit-function-declaration -Wno-reserved-user-defined-literal -Wno-shift-negative-value"
  export CFLAGS+=" $sameflags"
  export LDFLAGS+=" -arch arm64"
  export BUILD_SYSROOT_CFLAGS="-isysroot ${themacsysroot}"

  if [[ "$J316SAP" != "1" ]]; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install ldid xquartz
  fi
fi

# fix building libjawt
ln -s -f $CUPS_DIR/cups $ANDROID_INCLUDE/

#FREEMARKER=$PWD/freemarker-2.3.8/lib/freemarker.jar

cd openjdk

# Apply patches
#
# ThorCraft: every apply below used to end in "|| echo ...", so a patch set that
# stopped applying against a newer tag produced a silently under-patched JVM
# instead of a failed build. Fail hard instead.
applypatch() {
  echo "Applying $1"
  git apply --reject --whitespace=fix "$1" || {
    echo "git apply failed: $1" >&2
    exit 1
  }
}

git reset --hard
if [[ "$BUILD_IOS" != "1" ]]; then
  # jdk8u_android.diff used to carry a one-line cosmetic hunk retitling
  # PRODUCT_SUFFIX in common/autoconf/version-numbers. Its context included
  # "JDK_UPDATE_VERSION=482", so it stopped applying the moment the pin moved to
  # 8u502 and would break again on every future update. Done with sed instead,
  # which no longer cares what the update version is.
  sed -i 's/^PRODUCT_SUFFIX="Runtime Environment"$/PRODUCT_SUFFIX="Android Runtime Environment"/' \
    common/autoconf/version-numbers
  grep -q '^PRODUCT_SUFFIX="Android Runtime Environment"$' common/autoconf/version-numbers || {
    echo "failed to retitle PRODUCT_SUFFIX in common/autoconf/version-numbers" >&2
    exit 1
  }

  # config.sub must pass Android target triples through instead of delegating to
  # autoconf-config.sub, which does not know them. This used to be two hunks in
  # jdk8u_android.diff written against jdk8u's config.sub, so it always rejected
  # on aarch32, whose repo (aarch32-port-jdk8u) ships a structurally different
  # wrapper handling both aarch32- and aarch64- prefixes. An early passthrough
  # is equivalent to both hunks and does not care which wrapper is present.
  python3 - <<'PYEOF'
import io, sys
path = "common/autoconf/build-aux/config.sub"
marker = "# ThorCraft: pass Android target triples through"
src = io.open(path, encoding="utf-8", errors="surrogateescape").read()
if marker not in src:
    lines = src.split("\n")
    for i, ln in enumerate(lines):
        if ln.startswith("DIR="):
            lines[i+1:i+1] = [
                "",
                marker,
                'for __tc_arg in "$@"; do',
                '    case "$__tc_arg" in',
                '        *-android*) echo "$__tc_arg"; exit 0 ;;',
                "    esac",
                "done",
            ]
            break
    else:
        sys.exit("config.sub: no DIR= anchor found")
    io.open(path, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(lines))
print("config.sub: Android passthrough installed")
PYEOF

  applypatch ../patches/jdk8u_android.diff
  if [[ "$TARGET_JDK" != "aarch32" ]]; then
    applypatch ../patches/jdk8u_android_main.diff
  else
    applypatch ../patches/jdk8u_android_aarch32.diff
  fi
  if [[ "$TARGET_JDK" == "x86" ]]; then
    applypatch ../patches/jdk8u_android_page_trap_fix.diff
  fi
  # JDK-8360869 (in 8u502, not 8u482) added a configure guard that aborts when
  # TOOLCHAIN_TYPE is gcc, the target is aarch64, and the compiler's major
  # version is below 5, because GCC 4.x miscompiles HotSpot there. This build
  # passes --with-toolchain-type=gcc but compiles with the NDK's clang, whose
  # version string the guard misparses -- so it aborts on a compiler it was
  # never about, which is what kept the aarch64 pin stuck at 8u482.
  #
  # Detecting clang at that point in configure did not work (the guard still
  # fired), so neutralise the abort itself rather than depend on runtime
  # detection. The check still prints its result; only the fatal call is
  # dropped, and only in the generated script configure actually executes.
  if [[ "$TARGET_JDK" == "aarch64" ]]; then
    sed -i 's|as_fn_error $? "GCC < 5 may incorrectly compile HotSpot on aarch64. See JDK-8360869." "$LINENO" 5|: # ThorCraft: guard targets real GCC 4.x; this cross-build uses NDK clang|' \
      common/autoconf/generated-configure.sh
    if grep -q 'GCC < 5 may incorrectly compile HotSpot on aarch64' common/autoconf/generated-configure.sh; then
      echo "failed to neutralise the JDK-8360869 aarch64 guard" >&2
      exit 1
    fi
  fi
else
  git apply --reject --whitespace=fix ../patches/jdk8u_ios.diff || echo "git apply failed (ios patch set)"
  git apply --reject --whitespace=fix ../patches/jdk8u_ios_xattr.diff || echo "git apply failed (ios xattr patch set)"
  git apply --reject --whitespace=fix ../patches/jdk8u_ios_fix_clang.diff || echo "git apply failed (ios clang fix patch set)"
  git apply --reject --whitespace=fix ../patches/jdk8u_ios_mirror_mapping.diff || echo "git apply failed (ios mirror map patch set)"
fi

#   --with-extra-cxxflags="$CXXFLAGS -Dchar16_t=uint16_t -Dchar32_t=uint32_t" \
#   --with-extra-cflags="$CPPFLAGS" \
#   --with-sysroot="$(xcrun --sdk iphoneos --show-sdk-path)" \

# Let's print what's available
# bash configure --help

#   --with-freemarker-jar=$FREEMARKER \
#   --with-toolchain-type=clang \
#   --with-native-debug-symbols=none \
bash ./configure \
    --openjdk-target=$TARGET_PHYS \
    --with-extra-cflags="$CFLAGS" \
    --with-extra-cxxflags="$CFLAGS" \
    --with-extra-ldflags="$LDFLAGS" \
    --enable-option-checking=fatal \
    --with-jdk-variant=normal \
    --with-jvm-variants="${JVM_VARIANTS/AND/,}" \
    --with-cups-include=$CUPS_DIR \
    --with-devkit=$TOOLCHAIN \
    --with-debug-level=$JDK_DEBUG_LEVEL \
    --with-fontconfig-include=$ANDROID_INCLUDE \
    --with-freetype-lib=$FREETYPE_DIR/lib \
    --with-freetype-include=$FREETYPE_DIR/include/freetype2 \
    $AUTOCONF_x11arg $AUTOCONF_EXTRA_ARGS \
    --x-libraries=/usr/lib \
        $platform_args || \
error_code=$?
if [[ "$error_code" -ne 0 ]]; then
  echo "\n\nCONFIGURE ERROR $error_code , config.log:"
  cat config.log
  exit $error_code
fi

cd build/${JVM_PLATFORM}-${TARGET_JDK}-normal-${JVM_VARIANTS}-${JDK_DEBUG_LEVEL}
make JOBS=4 images || \
error_code=$?
if [[ "$error_code" -ne 0 ]]; then
  echo "Build failure, exited with code $error_code. Trying again."
  make JOBS=4 images
fi
