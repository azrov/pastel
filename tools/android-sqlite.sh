#!/bin/sh
# Builds SQLite for Android apps: framework/android/lib/<abi>/libsqlite3.so,
# for arm64-v8a, armeabi-v7a, x86_64 and x86, without the NDK.
#
# Android does not let apps load the phone's own SQLite (since Android 7), so
# every app that uses Pastel.Db carries this one; "pastel package apk" puts it
# in. The libraries are kept in the repository, so apps do not need these tools.
#
# Needs SQLite's amalgamation (sqlite3.c from sqlite.org), the C cross-compilers
# and their binutils (Ubuntu: sudo apt install gcc-aarch64-linux-gnu
# gcc-arm-linux-gnueabi gcc-i686-linux-gnu gcc binutils-x86-64-linux-gnu), and
# Pastel's stand-ins for Android's system libraries ("pastel doctor --install android").
#   sh tools/android-sqlite.sh path/to/sqlite3.c
#
# SQLite is compiled against the cross-compilers' C headers (glibc) and linked
# with Android's libc by name: the few differences are taken care of here —
# errno (shim.c), no stack protector and no _FORTIFY_SOURCE, 32-bit file
# offsets on 32-bit devices, temporary data in memory (Android has no /tmp),
# sysconf's numbers, no memory-mapped files (mremap is missing on older Android),
# 16 KB memory pages (newer phones; Google Play asks for it).
set -e
cd "$(dirname "$0")/.."
SRC="${1:?usage: sh tools/android-sqlite.sh path/to/sqlite3.c}"
STUBS="${PASTEL_CACHE:-$HOME/.pastel}/android"
WORK="$(mktemp -d)"
cat > "$WORK/shim.c" <<'EOS'
/* glibc's errno is __errno_location(); Android's libc calls it __errno() */
extern int *__errno(void);
int *__errno_location(void) { return __errno(); }
/* sysconf's numbers differ: glibc's _SC_PAGESIZE is 30, Android's 0x27 */
extern long sysconf(int);
long pastel_sysconf(int name) { return sysconf(name == 30 ? 0x27 : name); }
EOS
# 32-bit: glibc's large-file names, for Android versions whose libc lacks them
# (Android's own struct stat already has the 64-bit layout). No headers here,
# so that stat is not renamed stat64 again; Android's own functions win when it has them.
cat > "$WORK/shim32.c" <<'EOS'
typedef long long off64;
extern int open(const char *, int, ...);
extern int stat(const char *, void *);
extern int fstat(int, void *);
extern int lstat(const char *, void *);
extern int fcntl(int, int, ...);
extern void *mmap(void *, unsigned, int, int, int, long);
int open64(const char *p, int f, int m) { return open(p, f, m); }  /* Android adds O_LARGEFILE itself */
int stat64(const char *p, void *b) { return stat(p, b); }
int fstat64(int fd, void *b) { return fstat(fd, b); }
int lstat64(const char *p, void *b) { return lstat(p, b); }
int fcntl64(int fd, int cmd, void *arg) { return fcntl(fd, cmd, arg); }
void *mmap64(void *a, unsigned n, int p, int f, int fd, off64 o) { return mmap(a, n, p, f, fd, (long)o); }
EOS
FLAGS="-Os -fPIC -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -fvisibility=default -DNDEBUG
  -DSQLITE_THREADSAFE=1 -DSQLITE_TEMP_STORE=3 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DEFAULT_FOREIGN_KEYS=1
  -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_DQS=0
  -DHAVE_USLEEP=1 -DHAVE_LOCALTIME_R=1 -DHAVE_GMTIME_R=1 -DSQLITE_MAX_MMAP_SIZE=0 -DHAVE_MREMAP=0 -Dsysconf=pastel_sysconf"
build() {  # abi gcc binutils-prefix stub-dir extra-flags [32]
  ABI="$1"; CC="$2"; BIN="$3"; LIBS="$STUBS/$4/lib"; EXTRA="$5"
  command -v "$CC" >/dev/null || { echo "skipped $ABI: no $CC"; return; }
  [ -f "$LIBS/libc.so" ] || { echo "skipped $ABI: run pastel doctor --install android first ($LIBS)"; return; }
  OUT="framework/android/lib/$ABI"
  mkdir -p "$OUT"
  "$CC" $FLAGS $EXTRA -c "$SRC" -o "$WORK/sqlite3-$ABI.o"
  "$CC" -O2 -fPIC -fno-stack-protector $EXTRA -c "$WORK/shim.c" -o "$WORK/shim-$ABI.o"
  SHIM32=""
  if [ "$6" = 32 ]; then
    "$CC" -O2 -fPIC -fno-stack-protector -fno-builtin $EXTRA -c "$WORK/shim32.c" -o "$WORK/shim32-$ABI.o"
    SHIM32="$WORK/shim32-$ABI.o"
  fi
  # pieces of the C compiler's own library (64-bit division on 32-bit CPUs)
  LIBGCC="$("$CC" $EXTRA -print-libgcc-file-name)"
  "${BIN}ld" -shared -soname libsqlite3.so --hash-style=both -z noexecstack -z now --no-undefined-version \
    -z max-page-size=16384 -z common-page-size=16384 \
    -o "$OUT/libsqlite3.so" "$WORK/sqlite3-$ABI.o" "$WORK/shim-$ABI.o" $SHIM32 "$LIBGCC" -L"$LIBS" -lc -lm -ldl
  "${BIN}strip" --strip-unneeded "$OUT/libsqlite3.so"
  echo "built $OUT/libsqlite3.so ($(wc -c < "$OUT/libsqlite3.so") bytes)"
}
# 64-bit: file offsets are 64-bit anyway, without glibc's ...64 names;
# 32-bit: the 64-bit offsets (and Android's struct stat), 32-bit time like Android's
build arm64-v8a aarch64-linux-gnu-gcc aarch64-linux-gnu- arm64 "-DSQLITE_DISABLE_LFS"
build armeabi-v7a arm-linux-gnueabi-gcc arm-linux-gnueabi- arm "-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -marm -U_TIME_BITS -D_FILE_OFFSET_BITS=64" 32
build x86_64 gcc x86_64-linux-gnu- x86_64 "-DSQLITE_DISABLE_LFS"
build x86 i686-linux-gnu-gcc i686-linux-gnu- x86 "-U_TIME_BITS -D_FILE_OFFSET_BITS=64" 32
rm -rf "$WORK"
