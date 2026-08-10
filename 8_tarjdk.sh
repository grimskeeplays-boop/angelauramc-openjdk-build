#!/bin/bash
set -e
. setdevkitpath.sh

if [[ "$BUILD_IOS" != "1" ]]; then

unset AR AS CC CXX LD OBJCOPY RANLIB STRIP CPPFLAGS LDFLAGS
git clone https://github.com/termux/termux-elf-cleaner || true
cd termux-elf-cleaner
mkdir build
cd build
# NB: this -D__ANDROID_API__ has no effect on termux-elf-cleaner -- it reads its
# target from the --api-level flag below and otherwise defaults to 21. Kept only
# because upstream sets it.
export CFLAGS=-D__ANDROID_API__=${API}
cmake ..
make -j4
unset CFLAGS
cd ../..

findexec() { find $1 -type f -name "*" -not -name "*.o" -exec sh -c '
    case "$(head -n 1 "$1")" in
      ?ELF*) exit 0;;
      MZ*) exit 0;;
      #!*/ocamlrun*)exit0;;
    esac
exit 1
' sh {} \; -print
}

# --api-level is REQUIRED. termux-elf-cleaner defaults to api_level 21 and, for
# anything below 23, deletes DT_GNU_HASH (plus DT_VERSYM/VERNEED/VERDEF). The
# NDK linker emits only GNU hash at API >= 23, so leaving the default in place
# strips a library's ONLY hash table and Android then refuses to load it:
#   "empty/missing DT_HASH/DT_GNU_HASH ... (new hash type from the future?)"
# That is invisible below API 23, where the linker also emits DT_HASH as a
# fallback -- which is why this only appeared once the build moved to API 26.
findexec jreout | xargs -- ./termux-elf-cleaner/build/termux-elf-cleaner --api-level ${API}
findexec jdkout | xargs -- ./termux-elf-cleaner/build/termux-elf-cleaner --api-level ${API}

fi

cp -rv jre_override/lib/* jreout/lib/ || true

cd jreout

# Strip in place all .so files thanks to the ndk. KEEP_JVM_SYMBOLS=1 spares
# libjvm.so so crash stacks symbolize; note that only ever covered the server
# variant, so aarch32 (client) was stripped either way.
if [[ "${KEEP_JVM_SYMBOLS:-0}" == "1" ]]; then
  find ./ -name '*.so' ! -path './lib/server/libjvm.so' -execdir ${TOOLCHAIN}/bin/llvm-strip {} \;
else
  find ./ -name '*.so' -execdir ${TOOLCHAIN}/bin/llvm-strip {} \;
fi


tar cJf ../jre${TARGET_VERSION}-${TARGET_OS}-${TARGET_SHORT}-`date +%Y%m%d`-${JDK_DEBUG_LEVEL}.tar.xz .

cd ../jdkout
tar cJf ../jdk${TARGET_VERSION}-${TARGET_OS}-${TARGET_SHORT}-`date +%Y%m%d`-${JDK_DEBUG_LEVEL}.tar.xz .

# Remove jreout and jdkout
cd ..
rm -rf jreout jdkout

