#!/usr/bin/env bash
# PHP 7.2.34 / Ubuntu 18.04 x86_64, with the owner's original external modules.
ORIGINAL_EXTENSION_BASE_URL="https://github.com/ltech2025/download/releases/download/php7.2.3extensions"
IONCUBE_URL="$ORIGINAL_EXTENSION_BASE_URL/ioncube_loader_lin_7.2.so"

# Fingerprinted from /home/<user>/php_main/php; never substitute these binaries.
IONCUBE_SHA256="6e3adaff6ed9487ecf5fa73afe03886ff84262faabf8e5bd9c6f9555f1d03c0b"
GEOIP_BINARY_SHA256="f07f925766e9540f68da8a38db1b387f19ea1d9e9692192bf1c847ae7d5d532f"
MCRYPT_BINARY_SHA256="78aa9b8d11a920f562cde453a3f082a63d998b29cf3d2862f11d02f10c13f918"
IGBINARY_BINARY_SHA256="ebf370be6f312246072598e6be9f646b7181aad5c8b18fa22ae8733623334c76"
# Official sources below supply reference PHPT tests, not replacement binaries.
IGBINARY_VERSION="2.0.6RC1"
IGBINARY_SOURCE_URL="https://pecl.php.net/get/igbinary-${IGBINARY_VERSION}.tgz"
IGBINARY_SOURCE_SHA256="78c42e3167d4a178f852c4a617c5a88186ff22f91ac5c87ac00a5cd10432947f"
PHP_URL="https://museum.php.net/php7/php-7.2.34.tar.xz"
PHP_SHA256="409e11bc6a2c18707dfc44bc61c820ddfd81e17481470f3405ee7822d8379903"
PATCH_BASE="https://ppa.launchpadcontent.net/ondrej/php/ubuntu/pool/main/p/php7.2"
PATCH_VERSION="php7.2_7.2.34-66+ubuntu22.04.1+deb.sury.org+1"
PATCH_SHA256="f0dcdbb45c771a06a61eb6fac2b7e9ddb97afad7d945a719b8777eb0faa92190"
DSC_SHA256="ab23c05fe18fb9a28dc565c5eeb4b0d6018ac09e4f14ff43b8042264b7ec8229"
SIGNING_KEY="6A1AAD7AE5B401C6E259A7B257067BAA1314C7FC"
GEOIP_URL="https://pecl.php.net/get/geoip-1.1.1.tgz"
GEOIP_SHA256="b2d05c03019d46135c249b5a7fa0dbd43ca5ee98aea8ed807bc7aa90ac8c0f06"
PREFIX="/home/xtreamcodes/iptv_xtream_codes/php"
LIBRARY_PROFILE="production-bionic-curl3-ssl10-png12-v1"
OUTPUT="$PWD/php-build-output"
JOBS=2

# All build instructions are below in plain text. No embedded archive, downloaded
# helper script, old build kit, or files from the development VM are needed.
# wget fetches source/binary inputs; apt-get fetches Ubuntu packages.
# The accepted EOL mitigation disables session upload progress and skips PHP
# shutdown callbacks on OOM. igbinary is packaged, but not enabled by default.
set -Eeuo pipefail
umask 022
MODE=build WITH_TESTS=0 RUN= FINISH_RUN= CURRENT_LOG= FPM_PID= APT_TMP= TEST_TMP=
SCRIPT_PATH=$(realpath -- "${BASH_SOURCE[0]}")
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() {
    if [[ -n $FPM_PID ]]; then kill "$FPM_PID" 2>/dev/null || true; wait "$FPM_PID" 2>/dev/null || true; fi
    [[ -z $APT_TMP ]] || rm -rf -- "$APT_TMP"
    [[ -z $TEST_TMP ]] || rm -rf -- "$TEST_TMP"
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'rc=$?; printf "ERROR at line %s (status %s). Run: %s\n" "$LINENO" "$rc" "$RUN" >&2; if [[ -f $CURRENT_LOG ]]; then tail -n 20 "$CURRENT_LOG" >&2; fi; exit "$rc"' ERR

usage() {
    cat <<'HELP'
Run as a normal sudo-capable user on a fresh Ubuntu 18.04 x86_64 VM:
  bash build_php.sh
  bash build_php.sh --with-tests
  bash build_php.sh --jobs 2 --output-dir "$HOME/php-build-output"

All downloads use wget and HTTPS; SHA256 is checked before use. The patch
package also has its DSC signature checked against a pinned signer fingerprint.
Only source patches 0105, 0135 and 0159 are used. GeoIP 1.1.1, original mcrypt
(reported module version 7.2.3), igbinary 2.0.6RC1 and ionCube are downloaded
as the exact original .so files; their SHA256 is always checked before packaging.
OPcache, ZIP, SQLite, timelib/timezone and bundled PEAR come from PHP 7.2.34.
PHP links to the production libcurl3 7.58.0-2ubuntu2, OpenSSL 1.0.2n-1ubuntu5.6
and PNG 1.2.54-1ubuntu1 ABI. Their pinned Ubuntu packages are extracted privately
for compilation/testing; they are not installed system-wide or bundled in PHP.
The build VM may retain newer system libraries. Direct ELF dependencies and
versioned symbols are checked on every build, even without --with-tests.
igbinary stays inactive. Default: build/staging and packaging, without tests.
Sudo is used for Ubuntu dependencies only. Compilation/staging is unprivileged.

  --check-sources  Download/check public sources and apply patches in a new
                   scratch tree only. No sudo, compiler or vendor URLs needed.
                   Requires wget, gpg, patch, tar and xz already installed.
  --with-tests     Run extension/PHP/OPcache tests and runtime/ABI/CGI/FPM checks.
                   Without this flag, tests are recorded as SKIPPED.
  --finish-run DIR Resume packaging for an already compiled run
                   that stopped before packaging. No downloads or compilation.
                   Requires this original-extension profile; old rebuilt .so
                   files are rejected. Add --with-tests to run runtime/tests.
  --help           Show this help without starting work.

Output: php-build-output/run.XXXXXXXX/php/ and artifacts/*.tar.gz, with reports
and logs. The archive preserves the production prefix; no deployment is done.
With --with-tests, broad PHPT failures produce exit 2 AFTER packaging if the
mandatory local/security checks passed. Read reports before using the candidate.
PHP 7.2 is EOL. Target library/config and encoded application tests are separate.
HELP
}
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0;;
        --check-sources) MODE=check-sources; shift;;
        --with-tests) WITH_TESTS=1; shift;;
        --jobs|--output-dir|--finish-run)
            (($# >= 2)) || fail "Missing value for $1"
            [[ -n $2 ]] || fail "Empty value for $1"
            case "$1" in --jobs) JOBS=$2;; --output-dir) OUTPUT=$2;; --finish-run) MODE=finish-run; FINISH_RUN=$2;; esac
            shift 2;;
        *) fail "Unknown argument: $1";;
    esac
done
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || fail '--jobs must be positive.'
[[ $(id -u) != 0 ]] || fail 'Run without sudo; the script calls sudo for APT itself.'
[[ ! -e /home/xtreamcodes/iptv_xtream_codes ]] || fail 'Production application path exists; use a disposable build VM.'
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 18.04 && $(uname -m) == x86_64 ]] || fail 'Requires Ubuntu 18.04 x86_64.'
[[ $(getconf GNU_LIBC_VERSION) == 'glibc 2.27' ]] || fail 'Requires glibc 2.27.'
if [[ $MODE == build ]]; then
    [[ $IONCUBE_URL == https://?* ]] || fail 'Fill IONCUBE_URL at the top with a direct HTTPS URL to the original ionCube .so file.'
    [[ $ORIGINAL_EXTENSION_BASE_URL == https://?* ]] || fail 'Original extension base URL must use HTTPS.'
fi
if [[ $MODE == finish-run ]]; then
    RUN=$(realpath -- "$FINISH_RUN")
    [[ $RUN =~ ^/[a-zA-Z0-9_./-]+$ && ${RUN##*/} == run.* && -O $RUN ]] || fail 'Not an owned build run directory.'
    for item in reports/configure-options.txt reports/applied-patches.sha256 stage$PREFIX/bin/php; do
        [[ -f $RUN/$item ]] || fail "Incomplete run: missing $item"
    done
    [[ ! -e $RUN/artifacts && ! -e $RUN/stage/release-metadata ]] || fail 'This run already reached packaging; refusing to overwrite its artifacts.'
    for module in geoip mcrypt igbinary; do
        [[ -f $RUN/stage$PREFIX/lib/php/extensions/no-debug-non-zts-20170718/$module.so ]] || fail "Missing original extension: $module"
    done
    if ((WITH_TESTS)); then
        for spec in geoip-1.1.1 "igbinary-$IGBINARY_VERSION"; do
            [[ -d $RUN/$spec/tests ]] || fail "Missing extension tests: $spec"
        done
    fi
    [[ -d $RUN/php && -f $RUN/stage$PREFIX/lib/php/extensions/no-debug-non-zts-20170718/ioncube_loader_lin_7.2.so ]] || fail 'Build/staging has not completed.'
    if ((WITH_TESTS)); then
        [[ -f $RUN/php-source/run-tests.php ]] || fail 'Missing PHP test runner.'
    fi
    PREVIOUS=$(mktemp -d "$RUN/previous-checks.XXXXXXXX")
    cp -a "$RUN/reports" "$RUN/logs" "$PREVIOUS/"
else
    mkdir -p -- "$OUTPUT"
    OUTPUT=$(cd -- "$OUTPUT" && pwd -P)
    [[ $OUTPUT =~ ^/[a-zA-Z0-9_./-]+$ ]] || fail 'Use a build path without spaces or shell-special characters.'
    RUN=$(mktemp -d "$OUTPUT/run.XXXXXXXX")
    mkdir "$RUN/downloads" "$RUN/logs" "$RUN/reports" "$RUN/stage" "$RUN/tmp"
fi
exec > >(tee -a "$RUN/build.log") 2>&1
printf 'Run: %s\n' "$RUN"
export LC_ALL=C.UTF-8 TZ=UTC SOURCE_DATE_EPOCH=1601510400 PHP_INI_SCAN_DIR=
unset PHPRC CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBRARY_PATH LD_LIBRARY_PATH CONFIG_SITE \
    PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR || true
DEPS="$RUN/production-deps"
DEP_LIB="$DEPS/lib/x86_64-linux-gnu"
use_production_libraries() {
    [[ -f $RUN/reports/library-profile.txt && $(cat "$RUN/reports/library-profile.txt") == "$LIBRARY_PROFILE" ]] || \
        fail 'Run uses a different library profile; start a fresh build.'
    for library in libcurl.so.4 libssl.so.1.0.0 libcrypto.so.1.0.0 libpng12.so.0; do
        [[ -f $DEP_LIB/$library ]] || fail "Missing private production library: $library"
    done
    export CPPFLAGS="-I$DEPS/include -I$DEPS/include/x86_64-linux-gnu"
    export LDFLAGS="-L$DEP_LIB -Wl,-rpath-link,$DEP_LIB"
    export PKG_CONFIG_PATH="$DEP_LIB/pkgconfig" LD_LIBRARY_PATH="$DEP_LIB"
}
run_suite() {
    local label=$1 rc=0; shift
    printf 'Running %s; full output: %s/logs/%s.log\n' "$label" "$RUN" "$label"
    "$@" > "$RUN/logs/$label.log" 2>&1 || rc=$?
    printf '%s %s\n' "$label" "$rc" >> "$RUN/reports/test-status.txt"
    printf 'Finished %s (status %s)\n' "$label" "$rc"
    if ((rc != 0)); then TEST_FAILURES=1; fi
}

if [[ $MODE != finish-run ]]; then
# Dependency versions used for the selected Bionic build profile. No PPA binary
# packages are installed. Missing pinned versions are errors, never substitutions.
PACKAGES=(
    autoconf=2.69-11 automake=1:1.15.1-3ubuntu2 binutils=2.30-21ubuntu1~18.04.9
    bison=2:3.0.4.dfsg-1build1 build-essential=12.4ubuntu1
    ca-certificates=20230311ubuntu0.18.04.1 wget=1.19.4-1ubuntu2.2
    cpp-7=7.5.0-3ubuntu1~18.04 g++-7=7.5.0-3ubuntu1~18.04
    gcc=4:7.4.0-1ubuntu2.3 gcc-7=7.5.0-3ubuntu1~18.04 gnupg=2.2.4-1ubuntu1.6
    libbz2-dev=1.0.6-8.1ubuntu0.2 libc6-dev=2.27-3ubuntu1.6
    libcurl4=7.58.0-2ubuntu3.24 libfcgi-bin=2.4.0-10
    libfreetype6-dev=2.8.1-2ubuntu2.2 libgeoip1=1.6.12-1 libmcrypt4=2.5.8-3.3
    libpng-dev=1.6.34-1ubuntu0.18.04.2
    libtool=2.4.6-2 libxml2-dev=2.9.4+dfsg1-6.1ubuntu1.9
    libxslt1-dev=1.1.29-5ubuntu0.3 make=4.1-9.1ubuntu1 patch=2.7.6-2ubuntu1.1
    pkg-config=0.29.1-0ubuntu2 re2c=1.0.1-1 xz-utils=5.2.2-1.3
    zlib1g-dev=1:1.2.11.dfsg-0ubuntu2.2 openssl=1.1.1-1ubuntu2.1~18.04.23 netbase=5.4
)
install_dependencies() {
    command -v sudo >/dev/null || fail 'sudo is required.'
    APT_TMP=$(mktemp -d /tmp/php-build-apt.XXXXXXXX)
    chmod 755 "$APT_TMP"
    local archive=http://archive.ubuntu.com/ubuntu security=http://security.ubuntu.com/ubuntu
    local -a options=(-o "Dir::Etc::sourcelist=$APT_TMP/sources.list" -o Dir::Etc::sourceparts=-
        -o APT::Get::List-Cleanup=0 -o Acquire::Retries=3 -o Acquire::http::Timeout=30
        -o Acquire::https::Timeout=30 -o APT::Get::AllowUnauthenticated=false
        -o Acquire::AllowInsecureRepositories=false)
    write_sources() {
        printf 'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] %s %s main universe\n' \
            "$archive" bionic "$archive" bionic-updates "$security" bionic-security > "$APT_TMP/sources.list"
    }
    write_sources
    # Signed HTTP metadata bootstraps CA certificates; subsequent fetches use TLS.
    if ! sudo apt-get "${options[@]}" update; then
        archive=http://old-releases.ubuntu.com/ubuntu; security=$archive
        write_sources
        sudo apt-get "${options[@]}" update
    fi
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" -y --no-install-recommends install ca-certificates=20230311ubuntu0.18.04.1
    archive=${archive/http:/https:}; security=${security/http:/https:}
    write_sources
    sudo apt-get "${options[@]}" update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" -y --no-install-recommends install "${PACKAGES[@]}"
    local spec actual
    for spec in "${PACKAGES[@]}"; do
        actual=$(dpkg-query -W -f='${Version}' "${spec%%=*}")
        [[ $actual == "${spec#*=}" ]] || fail "Dependency mismatch: $spec installed=$actual"
    done
    rm -rf -- "$APT_TMP"; APT_TMP=
    dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > "$RUN/reports/build-environment.txt"
}
if [[ $MODE == build ]]; then install_dependencies; fi
for tool in wget gpg patch tar xz sha256sum; do command -v "$tool" >/dev/null || fail "Missing tool: $tool"; done

download() {
    local url=$1 name=$2 sha=$3
    printf 'Downloading %s\n' "$name"
    wget --https-only --tries=3 --timeout=60 --no-verbose -O "$RUN/downloads/$name.part" "$url"
    printf '%s  %s\n' "$sha" "$RUN/downloads/$name.part" | sha256sum --check --status
    mv -- "$RUN/downloads/$name.part" "$RUN/downloads/$name"
    printf '%s  %s\n' "$sha" "$name" >> "$RUN/reports/downloads.sha256"
}
download "$PHP_URL" php-7.2.34.tar.xz "$PHP_SHA256"
download "$PATCH_BASE/$PATCH_VERSION.debian.tar.xz" patches.tar.xz "$PATCH_SHA256"
download "$PATCH_BASE/$PATCH_VERSION.dsc" patches.dsc "$DSC_SHA256"
download "$GEOIP_URL" geoip-1.1.1.tgz "$GEOIP_SHA256"
download "$IGBINARY_SOURCE_URL" "igbinary-$IGBINARY_VERSION.tgz" "$IGBINARY_SOURCE_SHA256"
# Check the version of the reference igbinary test source.
tar -xOf "$RUN/downloads/igbinary-$IGBINARY_VERSION.tgz" "igbinary-$IGBINARY_VERSION/src/php7/igbinary.h" > "$RUN/reports/igbinary-source-header.txt"
grep -Fxq "#define PHP_IGBINARY_VERSION \"$IGBINARY_VERSION\"" "$RUN/reports/igbinary-source-header.txt"

# The expected source hashes and signer were established during the backport
# audit. The fetched public key must contain the exact pinned fingerprint;
# a keyserver's descriptive name or email is not treated as proof of identity.
mkdir -m 700 "$RUN/gnupg"
wget --https-only --tries=3 --timeout=60 --no-verbose -O "$RUN/downloads/signer.asc" \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$SIGNING_KEY"
gpg --homedir "$RUN/gnupg" --batch --import "$RUN/downloads/signer.asc" > "$RUN/logs/key-import.log" 2>&1
gpg --homedir "$RUN/gnupg" --batch --with-colons --fingerprint "$SIGNING_KEY" | \
    awk -F: -v wanted="$SIGNING_KEY" '$1=="fpr" && $10==wanted {found=1} END {exit !found}'
gpg --homedir "$RUN/gnupg" --batch --no-auto-key-retrieve --status-fd 1 \
    --verify "$RUN/downloads/patches.dsc" > "$RUN/reports/source-signature.txt" 2>&1
grep -Fq "[GNUPG:] VALIDSIG $SIGNING_KEY " "$RUN/reports/source-signature.txt"
awk '/^Checksums-Sha256:/{on=1;next} on && /^ /{print;next} on{exit}' "$RUN/downloads/patches.dsc" > "$RUN/reports/signed-source-hashes.txt"
grep -Fq " $PHP_SHA256 " "$RUN/reports/signed-source-hashes.txt"
grep -Fq " $PATCH_SHA256 " "$RUN/reports/signed-source-hashes.txt"

# Extract only authenticated, pinned archives into this invocation's empty tree.
mkdir "$RUN/php-source" "$RUN/patch-source"
tar -xJf "$RUN/downloads/php-7.2.34.tar.xz" --strip-components=1 --no-same-owner -C "$RUN/php-source"
tar -xJf "$RUN/downloads/patches.tar.xz" --no-same-owner -C "$RUN/patch-source"
PATCHES=(
    0105-Introduce-max_multipart_body_parts-INI.patch
    0135-backport-ZSTR_MAX_LEN.patch
    0159-Avoid-state-corruption-via-bailout.patch
)
PATCH_HASHES=(
    51e0a7758fce1fa44f0804313307171adb209504e0951b07f7fd2f1bc6c6a604
    b4da10ce4bb9aaf57dc3de71f21d200a5a331aec7c34b8c7b946b1db3b9c7e1f
    35f4820ab80594899db860be6f6d695657509d6186a830fefd5f442bc2bd0330
)
for i in "${!PATCHES[@]}"; do
    file="$RUN/patch-source/debian/patches/${PATCHES[$i]}"
    printf '%s  %s\n' "${PATCH_HASHES[$i]}" "$file" | sha256sum --check --status
    patch --directory="$RUN/php-source" --batch --forward --fuzz=0 -p1 < "$file"
    printf '%s  %s\n' "${PATCH_HASHES[$i]}" "${PATCHES[$i]}" >> "$RUN/reports/applied-patches.sha256"
done
if grep -R -n -E 'secure_dns_telemetry|telemetry_check|php-telemetry' "$RUN/php-source/main" "$RUN/php-source/sapi" "$RUN/php-source/Zend"; then
    fail 'Unexpected telemetry code.'
fi
if [[ $MODE == check-sources ]]; then
    printf 'PASS: public downloads, hashes, DSC signature, and exact three patches. No build started.\nReports: %s/reports\n' "$RUN"
    exit 0
fi
download "$IONCUBE_URL" ioncube_loader_lin_7.2.so "$IONCUBE_SHA256"
download "$ORIGINAL_EXTENSION_BASE_URL/geoip.so" geoip.so "$GEOIP_BINARY_SHA256"
download "$ORIGINAL_EXTENSION_BASE_URL/mcrypt.so" mcrypt.so "$MCRYPT_BINARY_SHA256"
download "$ORIGINAL_EXTENSION_BASE_URL/igbinary.so" igbinary.so "$IGBINARY_BINARY_SHA256"

# Exact runtime packages from the production inventory. Ubuntu signed package
# metadata authenticates curl/PNG hashes; Launchpad's published-binary metadata
# authenticates the superseded OpenSSL packages. Headers for curl are from its
# matching 7.58.0 source archive (hash recorded in Ubuntu's curl3 DSC).
# Host libcurl4 supplies common transitive runtime dependencies only. Its headers
# and libraries must never be selected for PHP; the ELF checks below enforce it.
UBUNTU_POOL=https://archive.ubuntu.com/ubuntu/pool
download "$UBUNTU_POOL/universe/c/curl3/libcurl3_7.58.0-2ubuntu2_amd64.deb" libcurl3.deb \
    26d8e98614a55013b35afac465081ec17c9d931ee11f648bca7c3cbaefb404af
download "$UBUNTU_POOL/universe/c/curl3/curl3_7.58.0.orig.tar.gz" curl-headers.tar.gz \
    cc245bf9a1a42a45df491501d97d5593392a03f7b4f07b952793518d97666115
download https://launchpadlibrarian.net/523563171/libssl1.0.0_1.0.2n-1ubuntu5.6_amd64.deb libssl10.deb \
    480e64edb60da232a3de6b97669beba8deabe8641457912722a90fa8b3f04f0b
download https://launchpadlibrarian.net/523563167/libssl1.0-dev_1.0.2n-1ubuntu5.6_amd64.deb libssl10-dev.deb \
    4332afc53b4f8ded7995441c052c8814dbd104769c98c9229d404fc7cfaf8db0
download "$UBUNTU_POOL/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_amd64.deb" libpng12.deb \
    1644e3936830ed3cf3ab7fac64de99f38e16f7be001ce7947600789ce85e7bcc
download "$UBUNTU_POOL/main/libp/libpng/libpng12-dev_1.2.54-1ubuntu1_amd64.deb" libpng12-dev.deb \
    953634e3b69f112b1aee2f1f0200411e488f170e9f1fb07492e1fe80537e93e7
mkdir -p "$RUN/dependency-packages" "$DEPS/include" "$DEP_LIB/pkgconfig"
for package in libcurl3 libssl10 libssl10-dev libpng12 libpng12-dev; do
    dpkg-deb -x "$RUN/downloads/$package.deb" "$RUN/dependency-packages"
    dpkg-deb -f "$RUN/downloads/$package.deb" Package Version Architecture >> "$RUN/reports/production-dependency-packages.txt"
done
cp -a "$RUN/dependency-packages/usr/include/." "$DEPS/include/"
cp -a "$RUN/dependency-packages/usr/lib/x86_64-linux-gnu/"libcurl.so* \
    "$RUN/dependency-packages/usr/lib/x86_64-linux-gnu/"libssl.so* \
    "$RUN/dependency-packages/usr/lib/x86_64-linux-gnu/"libcrypto.so* \
    "$RUN/dependency-packages/lib/x86_64-linux-gnu/"libpng12.so* "$DEP_LIB/"
ln -s libcurl.so.4 "$DEP_LIB/libcurl.so"
ln -s libpng12.so.0 "$DEP_LIB/libpng.so"
mkdir "$RUN/curl-headers"
tar -xzf "$RUN/downloads/curl-headers.tar.gz" --no-same-owner --strip-components=1 -C "$RUN/curl-headers"
cp -a "$RUN/curl-headers/include/curl" "$DEPS/include/"
cat > "$DEP_LIB/pkgconfig/libcurl.pc" <<CURL_PC
prefix=$DEPS
libdir=$DEP_LIB
includedir=$DEPS/include
supported_features=SSL
Name: libcurl
Description: Production Ubuntu libcurl3 with matching upstream headers
Version: 7.58.0
Libs: -L$DEP_LIB -lcurl
Cflags: -I$DEPS/include
CURL_PC
printf '%s\n' "$LIBRARY_PROFILE" > "$RUN/reports/library-profile.txt"
use_production_libraries

# Compile PHP itself, including OPcache, with the production prefix embedded.
# Removed core flags (mysql/mcrypt etc.) are not passed to PHP 7.2 configure.
cd "$RUN/php-source"
FLAGS=(
    "--prefix=$PREFIX" "--mandir=$PREFIX/php/man" "--with-config-file-path=$PREFIX/lib"
    --with-zlib-dir --with-freetype-dir --enable-mbstring --enable-calendar "--with-curl=$DEPS"
    "--with-png-dir=$DEPS"
    --with-gd --disable-rpath --with-bz2 --with-zlib --enable-sockets --enable-sysvsem
    --enable-sysvshm --enable-pcntl --enable-mbregex --enable-exif --enable-bcmath
    --with-mhash --enable-zip --with-pcre-regex --with-pdo-mysql=mysqlnd --with-mysqli=mysqlnd
    "--with-openssl=$DEPS" --with-fpm-user=xtreamcodes --with-fpm-group=xtreamcodes
    --with-libdir=/lib/x86_64-linux-gnu --with-gettext --with-xmlrpc --with-xsl
    --enable-opcache --enable-fpm --enable-static --enable-cli --enable-cgi --enable-phpdbg
    --disable-debug --disable-maintainer-zts --without-pear
)
printf '%s\n' "${FLAGS[@]}" > "$RUN/reports/configure-options.txt"
step() {
    local label=$1; shift
    CURRENT_LOG="$RUN/logs/$label.log"
    printf '%s (log: %s)\n' "$label" "$CURRENT_LOG"
    "$@" > "$CURRENT_LOG" 2>&1
}
step configure ./configure "${FLAGS[@]}"
if grep -E 'unrecognized options|WARNING:.*unsupported' "$CURRENT_LOG"; then fail 'Unsupported configure option.'; fi
step compile make -j"$JOBS"
step install make INSTALL_ROOT="$RUN/stage" install
DEST="$RUN/stage$PREFIX"
PHP="$DEST/bin/php"
EXT="$DEST/lib/php/extensions/no-debug-non-zts-20170718"
# Bundled PEAR is covered by the official PHP archive hash; packagingroot is
# explicit so the installer cannot write into the live production prefix.
step pear env INSTALL_ROOT="$RUN/stage" "$PHP" -n -d memory_limit=-1 \
    pear/install-pear-nozlib.phar -d "$PREFIX/lib/php" -b "$PREFIX/bin"

# Keep reference tests for --with-tests / --finish-run. Do not rebuild the
# external modules: mcrypt's original source is unavailable, and binary hashes
# preserve the exact original versions, compiled features and reflected APIs.
for spec in geoip-1.1.1 "igbinary-$IGBINARY_VERSION"; do
    mkdir "$RUN/$spec"
    tar -xzf "$RUN/downloads/$spec.tgz" --strip-components=1 --no-same-owner -C "$RUN/$spec" "$spec"
done
for module in ioncube_loader_lin_7.2 geoip mcrypt igbinary; do
    install -m 755 "$RUN/downloads/$module.so" "$EXT/"
done
# Delete only default FPM configurations from this NEW staged installation.
find "$DEST/etc" -type f -delete
ln -s "stage$PREFIX" "$RUN/php"
fi

use_production_libraries
DEST="$RUN/stage$PREFIX"
PHP="$DEST/bin/php"
EXT="$DEST/lib/php/extensions/no-debug-non-zts-20170718"
# Always enforce the target library ABI; --finish-run cannot reuse the old build.
# PNG16 may appear transitively through FreeType, as it does in production.
for binary in bin/php bin/php-cgi bin/phpdbg sbin/php-fpm; do
    label=${binary//\//-}
    readelf -d "$DEST/$binary" > "$RUN/reports/$label-needed.txt"
    readelf -V "$DEST/$binary" > "$RUN/reports/$label-symbol-versions.txt"
    for library in libcurl.so.4 libssl.so.1.0.0 libcrypto.so.1.0.0 libpng12.so.0; do
        grep -Fq "[$library]" "$RUN/reports/$label-needed.txt" || fail "$binary lacks $library"
    done
    if grep -Eq 'libssl\.so\.1\.1|libcrypto\.so\.1\.1|libpng16\.so|RPATH|RUNPATH' "$RUN/reports/$label-needed.txt"; then
        fail "$binary has the wrong direct libraries or an embedded library search path."
    fi
    grep -q 'Name: CURL_OPENSSL_3 ' "$RUN/reports/$label-symbol-versions.txt" || fail "$binary lacks CURL_OPENSSL_3"
    if grep -Eq 'Name: (CURL_OPENSSL_4|OPENSSL_1_1)' "$RUN/reports/$label-symbol-versions.txt"; then
        fail "$binary requires newer cURL/OpenSSL symbols."
    fi
    ldd "$DEST/$binary" > "$RUN/reports/$label-ldd.txt" 2>&1
    if grep -q 'not found' "$RUN/reports/$label-ldd.txt"; then fail "$binary has unresolved dependencies."; fi
done
"$PHP" -n -r 'if (strpos(OPENSSL_VERSION_TEXT,"OpenSSL 1.0.2n ")!==0 || curl_version()["version"]!=="7.58.0") exit(1); echo OPENSSL_VERSION_TEXT,"\n",curl_version()["ssl_version"],"\n";' \
    > "$RUN/reports/production-library-runtime.txt"
printf 'PASS: production cURL/OpenSSL/PNG direct ABI and runtime checks.\n'
# Artifact identity is a packaging requirement even when tests are disabled.
# This also prevents --finish-run from silently packaging the old rebuilt profile.
printf '%s  %s\n' \
    "$IONCUBE_SHA256" ioncube_loader_lin_7.2.so \
    "$GEOIP_BINARY_SHA256" geoip.so \
    "$MCRYPT_BINARY_SHA256" mcrypt.so \
    "$IGBINARY_BINARY_SHA256" igbinary.so > "$RUN/reports/original-extensions.sha256"
(cd "$EXT" && sha256sum --check "$RUN/reports/original-extensions.sha256") || \
    fail 'External modules differ from the original fingerprint. Start a new build with this script.'
export TMPDIR="$RUN/tmp" TEST_PHP_EXECUTABLE="$PHP" NO_INTERACTION=1 REPORT_EXIT_STATUS=1
TEST_FAILURES=0
: > "$RUN/reports/test-status.txt"

if ((WITH_TESTS)); then
printf 'ENABLED: --with-tests\n' > "$RUN/reports/test-mode.txt"
for spec in geoip-1.1.1 "igbinary-$IGBINARY_VERSION"; do
    cd "$RUN/$spec"
    run_suite "$spec-tests" "$PHP" -n "$RUN/php-source/run-tests.php" -n -d "extension=$EXT/${spec%%-*}.so" tests
done

# Mandatory runtime/layout/ABI checks. Any failure stops before packaging.
printf 'Checking runtime, layout, ABI and modules...\n'
CURRENT_LOG="$RUN/reports/runtime-checks.txt"
for tool in bin/php bin/php-cgi bin/phpdbg sbin/php-fpm bin/phpize bin/php-config bin/phar bin/phar.phar bin/pear bin/pecl bin/peardev; do
    [[ -x $DEST/$tool ]] || fail "Missing executable: $tool"
done
for dir in include/php lib/php/build lib/php/PEAR php/man; do [[ -d $DEST/$dir ]] || fail "Missing directory: $dir"; done
[[ $("$DEST/bin/php-config" --prefix) == "$PREFIX" ]] || fail 'Wrong embedded prefix.'
# PHP 7.2 php-config has no --phpapi option. Read the runtime ABI instead.
# Exclude INFO_ENVIRONMENT/INFO_VARIABLES to keep host credentials out of reports.
"$PHP" -n -r 'phpinfo(INFO_GENERAL | INFO_CONFIGURATION | INFO_MODULES);' > "$RUN/reports/php-info.txt"
grep -Fxq 'PHP API => 20170718' "$RUN/reports/php-info.txt" || fail 'Wrong PHP API.'
grep -Fxq 'PHP Extension => 20170718' "$RUN/reports/php-info.txt" || fail 'Wrong PHP extension API.'
grep -q '^Zend Extension => 320170718$' "$RUN/reports/php-info.txt"
"$PHP" -n -r 'exit(PHP_VERSION==="7.2.34" && !PHP_ZTS && !PHP_DEBUG ? 0 : 1);'
"$DEST/bin/php-cgi" -n -v > "$RUN/reports/cgi-version.txt"
# phpdbg uses uppercase -V for version; lowercase -v enters the debugger.
"$DEST/bin/phpdbg" -n -V > "$RUN/reports/phpdbg-version.txt"
"$DEST/sbin/php-fpm" -n -v > "$RUN/reports/fpm-version.txt"
"$PHP" -n -r '$x=get_loaded_extensions(); sort($x); echo implode("\n",$x),"\n";' > "$RUN/reports/builtin-modules.txt"
printf '%s\n' bcmath bz2 calendar Core ctype curl date dom exif fileinfo filter gd gettext hash iconv json libxml mbstring mysqli mysqlnd openssl pcntl pcre PDO pdo_mysql pdo_sqlite Phar posix Reflection session SimpleXML sockets SPL sqlite3 standard sysvsem sysvshm tokenizer xml xmlreader xmlrpc xmlwriter xsl zip zlib | LC_ALL=C sort > "$RUN/reports/expected-builtin-modules.txt"
diff -u "$RUN/reports/expected-builtin-modules.txt" "$RUN/reports/builtin-modules.txt"
"$DEST/sbin/php-fpm" -n -m > "$RUN/reports/fpm-modules-raw.txt"
awk '/^\[PHP Modules\]$/{on=1;next} /^\[Zend Modules\]$/{on=0} on && NF' \
    "$RUN/reports/fpm-modules-raw.txt" | LC_ALL=C sort > "$RUN/reports/fpm-builtin-modules.txt"
{ cat "$RUN/reports/expected-builtin-modules.txt"; printf 'cgi-fcgi\n'; } | \
    LC_ALL=C sort > "$RUN/reports/expected-fpm-builtin-modules.txt"
diff -u "$RUN/reports/expected-fpm-builtin-modules.txt" "$RUN/reports/fpm-builtin-modules.txt"
for file in "$PHP" "$DEST/bin/php-cgi" "$DEST/bin/phpdbg" "$DEST/sbin/php-fpm" "$EXT"/*.so; do
    ldd "$file" > "$RUN/reports/ldd-$(basename "$file").txt"
    if grep -q 'not found' "$RUN/reports/ldd-$(basename "$file").txt"; then fail "Missing library: $file"; fi
    readelf -d "$file" > "$RUN/reports/elf-$(basename "$file").txt"
    if grep -Eq '\((RPATH|RUNPATH)\)' "$RUN/reports/elf-$(basename "$file").txt"; then fail "Unexpected RPATH: $file"; fi
done
printf '%s  %s\n' "$IONCUBE_SHA256" "$EXT/ioncube_loader_lin_7.2.so" | sha256sum --check

# Short Unix socket paths avoid sockaddr_un limits on long user output paths.
TEST_TMP=$(mktemp -d /tmp/php72-test.XXXXXXXX)
cat > "$TEST_TMP/php.ini" <<INI
zend_extension=$EXT/ioncube_loader_lin_7.2.so
zend_extension=$EXT/opcache.so
extension=$EXT/geoip.so
extension=$EXT/mcrypt.so
opcache.enable=1
opcache.enable_cli=1
opcache.file_update_protection=0
date.timezone=UTC
error_reporting=32767
display_errors=1
log_errors=1
error_log=$TEST_TMP/php-errors.log
session.save_path=$TEST_TMP
upload_tmp_dir=$TEST_TMP
INI
cat > "$TEST_TMP/runtime.php" <<'PHPTEST'
<?php
function need($ok, $label) { if (!$ok) throw new Exception($label); }
need(PHP_VERSION === '7.2.34' && !PHP_ZTS && !PHP_DEBUG, 'version/NTS');
foreach (['ionCube Loader','Zend OPcache','geoip','mcrypt'] as $m) need(extension_loaded($m), $m);
need(!extension_loaded('igbinary'), 'igbinary inactive');
need((string)ioncube_loader_iversion() === '100203', 'original ionCube version');
need(phpversion('geoip') === '1.1.1' && is_array(geoip_db_get_all_info()), 'GeoIP API');
need(phpversion('Zend OPcache') === '7.2.34', 'OPcache version');
need(phpversion('mcrypt') === '7.2.3', 'original mcrypt module version');
foreach (['mcrypt_encrypt','mcrypt_decrypt'] as $fn) {
    need((new ReflectionFunction($fn))->getNumberOfRequiredParameters()===5, 'original mcrypt API: '.$fn);
}
$key=str_repeat('k',32); $iv=str_repeat('i',16); $plain='local-roundtrip';
$enc=@mcrypt_encrypt(MCRYPT_RIJNDAEL_128,$key,$plain,MCRYPT_MODE_CBC,$iv);
need(rtrim(@mcrypt_decrypt(MCRYPT_RIJNDAEL_128,$key,$enc,MCRYPT_MODE_CBC,$iv),"\0")===$plain,'mcrypt roundtrip');
$gold=@mcrypt_encrypt(MCRYPT_RIJNDAEL_128,str_repeat('K',16),'compatibility-probe',MCRYPT_MODE_CBC,str_repeat('I',16));
need(bin2hex($gold)==='be4edbf410b1cbc70d42cb4d200025d99447e15a4a9c80dcb0bfef05f0e1ac95', 'original mcrypt ciphertext');
need(openssl_decrypt(openssl_encrypt($plain,'AES-128-CBC',$key,0,$iv),'AES-128-CBC',$key,0,$iv)===$plain,'OpenSSL roundtrip');
$gd=gd_info(); need($gd['PNG Support'] && $gd['FreeType Support'] && !$gd['JPEG Support'],'GD features');
$im=imagecreatetruecolor(2,2); ob_start(); imagepng($im); $png=ob_get_clean(); need(imagecreatefromstring($png)!==false,'PNG roundtrip');
need(function_exists('mhash') && function_exists('mhash_keygen_s2k'),'mhash');
need(mb_strlen('Shqip','UTF-8')===5,'mbstring');
$db=new PDO('sqlite::memory:'); need((int)$db->query('select 42')->fetchColumn()===42,'SQLite');
$status=opcache_get_status(false); need($status['opcache_enabled'],'OPcache');
echo json_encode(['ok'=>true,'pid'=>getmypid(),'hits'=>$status['opcache_statistics']['hits']]),"\n";
PHPTEST
"$PHP" -c "$TEST_TMP/php.ini" "$TEST_TMP/runtime.php" > "$CURRENT_LOG" 2> "$RUN/reports/runtime-stderr.txt"
grep -q '"ok":true' "$CURRENT_LOG"
[[ ! -s $RUN/reports/runtime-stderr.txt ]] || fail 'Runtime emitted unexpected stderr.'
printf 'mcrypt-original-runtime 0\n' >> "$RUN/reports/test-status.txt"
"$PHP" -n -d "extension=$EXT/geoip.so" --ri geoip > "$RUN/reports/geoip-info.txt"
grep -Fxq 'geoip library version => 1006000' "$RUN/reports/geoip-info.txt" || fail 'Wrong original GeoIP compile-time library version.'
"$PHP" -n -d "extension=$EXT/mcrypt.so" --ri mcrypt > "$RUN/reports/mcrypt-info.txt"
"$PHP" -n -d "extension=$EXT/igbinary.so" --ri igbinary > "$RUN/reports/igbinary-info.txt" 2> "$RUN/reports/igbinary-info-stderr.txt"
grep -Fxq "igbinary version => $IGBINARY_VERSION" "$RUN/reports/igbinary-info.txt"
grep -Fxq 'igbinary APC serializer ABI => no' "$RUN/reports/igbinary-info.txt"
grep -Fxq 'igbinary session support => yes' "$RUN/reports/igbinary-info.txt"
grep -Fxq 'igbinary.compact_strings => On => On' "$RUN/reports/igbinary-info.txt"
"$PHP" -n -d "extension=$EXT/igbinary.so" -d "session.save_path=$TEST_TMP" -d session.serialize_handler=igbinary \
    -r '$v=["local",42,null]; if(phpversion("igbinary")!==$argv[1] || igbinary_unserialize(igbinary_serialize($v))!==$v) exit(1); if(!session_start()) exit(1); $_SESSION=["probe"=>$v]; $s=session_encode(); $_SESSION=[]; if(!session_decode($s) || $_SESSION!==["probe"=>$v]) exit(1); session_destroy(); echo "igbinary ",phpversion("igbinary")," value/session roundtrips PASS\n";' \
    "$IGBINARY_VERSION" > "$RUN/reports/igbinary-test.txt" 2> "$RUN/reports/igbinary-stderr.txt"
[[ ! -s $RUN/reports/igbinary-stderr.txt && ! -s $RUN/reports/igbinary-info-stderr.txt ]] || fail 'Original igbinary emitted an unexpected warning.'

# Bounded OOM must exit 1 without running a registered shutdown callback.
cat > "$TEST_TMP/oom.php" <<'PHPTEST'
<?php register_shutdown_function(function(){file_put_contents(__DIR__.'/shutdown-ran','yes');}); $x=str_repeat('x',64*1024*1024);
PHPTEST
OOM_RC=0
timeout 15 "$PHP" -n -d memory_limit=8M "$TEST_TMP/oom.php" > "$RUN/reports/oom.txt" 2>&1 || OOM_RC=$?
[[ $OOM_RC == 1 && ! -e $TEST_TMP/shutdown-ran ]] || fail 'OOM mitigation check failed.'
grep -q 'Allowed memory size' "$RUN/reports/oom.txt"

# CGI multipart upload still works, while upload-progress state stays disabled.
cat > "$TEST_TMP/upload.php" <<'PHPTEST'
<?php session_start(); echo json_encode(['progress'=>isset($_SESSION['upload_progress_probe']),'upload_ok'=>isset($_FILES['file']) && $_FILES['file']['error']===0]); session_destroy();
PHPTEST
printf '%b' '--LOCAL\r\nContent-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\nprobe\r\n--LOCAL\r\nContent-Disposition: form-data; name="file"; filename="test.txt"\r\nContent-Type: text/plain\r\n\r\nlocal\r\n--LOCAL--\r\n' > "$TEST_TMP/body"
env REDIRECT_STATUS=1 REQUEST_METHOD=POST SCRIPT_FILENAME="$TEST_TMP/upload.php" \
    CONTENT_TYPE='multipart/form-data; boundary=LOCAL' CONTENT_LENGTH="$(wc -c < "$TEST_TMP/body")" HTTP_COOKIE=PHPSESSID=localcontrol \
    timeout 15 "$DEST/bin/php-cgi" -n -d "session.save_path=$TEST_TMP" -d "upload_tmp_dir=$TEST_TMP" \
    -d session.upload_progress.enabled=1 -d session.upload_progress.cleanup=0 \
    -d session.upload_progress.freq=1 -d session.upload_progress.min_freq=0 \
    < "$TEST_TMP/body" > "$RUN/reports/upload.txt" 2> "$RUN/reports/upload-stderr.txt"
grep -q '"progress":false,"upload_ok":true' "$RUN/reports/upload.txt"
[[ ! -s $RUN/reports/upload-stderr.txt ]] || fail 'CGI upload emitted unexpected stderr.'

# Synthetic FPM checks use one worker, a private socket and no production data.
cat > "$TEST_TMP/fpm.conf" <<CONF
[global]
daemonize=no
error_log=$TEST_TMP/fpm.log
[synthetic]
listen=$TEST_TMP/fpm.sock
listen.mode=0600
pm=ondemand
pm.max_children=1
pm.process_idle_timeout=60s
catch_workers_output=yes
security.limit_extensions=.php
CONF
"$DEST/sbin/php-fpm" -c "$TEST_TMP/php.ini" -y "$TEST_TMP/fpm.conf" -t > "$RUN/reports/fpm-config.txt" 2>&1
"$DEST/sbin/php-fpm" -c "$TEST_TMP/php.ini" -y "$TEST_TMP/fpm.conf" -F > "$RUN/logs/fpm-process.log" 2>&1 &
FPM_PID=$!
for ((i=0;i<100;i++)); do [[ ! -S $TEST_TMP/fpm.sock ]] || break; sleep 0.1; done
[[ -S $TEST_TMP/fpm.sock ]] || fail 'FPM did not create its socket.'
request() {
    env SCRIPT_FILENAME="$TEST_TMP/$1.php" SCRIPT_NAME="/$1.php" REQUEST_METHOD=GET \
        REQUEST_URI="/$1.php" REDIRECT_STATUS=200 SERVER_PROTOCOL=HTTP/1.1 \
        PHP_VALUE="${3:-}" timeout 15 cgi-fcgi -bind -connect "$TEST_TMP/fpm.sock" > "$RUN/reports/$2.txt" 2>&1
}
json_field() {
    "$PHP" -n -r '$s=file_get_contents($argv[1]); $p=strpos($s,"{\"ok\":"); if($p===false) exit(1); $j=json_decode(substr($s,$p),true); if(!$j || empty($j["ok"])) exit(1); echo $j[$argv[2]];' "$RUN/reports/$1.txt" "$2"
}
for i in 1 2 3; do request runtime "fpm-$i"; done
PID1=$(json_field fpm-1 pid)
[[ $(json_field fpm-2 pid) == "$PID1" && $(json_field fpm-3 pid) == "$PID1" ]] || fail 'FPM worker changed unexpectedly.'
HITS1=$(json_field fpm-1 hits); HITS3=$(json_field fpm-3 hits)
((HITS3 > HITS1)) || fail 'OPcache did not reuse compiled scripts.'
cat > "$TEST_TMP/producer.php" <<'PHPTEST'
<?php echo 'PID='.getmypid()."\n"; set_error_handler(function(){throw new Exception('synthetic-handler');}); trigger_error('producer');
PHPTEST
request producer state-producer
grep -q "PID=$PID1" "$RUN/reports/state-producer.txt"
grep -q synthetic-handler "$RUN/reports/state-producer.txt"
request runtime state-consumer mbstring.internal_encoding=UTF-8
[[ $(json_field state-consumer pid) == "$PID1" ]] || fail 'FPM state-reset check failed.'
grep -q 'Use of mbstring.internal_encoding is deprecated' "$RUN/reports/state-consumer.txt" "$TEST_TMP/php-errors.log" "$TEST_TMP/fpm.log"
request oom fpm-oom memory_limit=8M || true
request runtime fpm-after-oom
[[ $(json_field fpm-after-oom pid) != "$PID1" && ! -e $TEST_TMP/shutdown-ran ]] || fail 'FPM OOM worker replacement failed.'
kill "$FPM_PID"; wait "$FPM_PID" || true; FPM_PID=
[[ ! -S $TEST_TMP/fpm.sock ]] || fail 'FPM did not remove the socket.'
cp "$TEST_TMP/fpm.log" "$RUN/logs/fpm.log"
printf 'PASS: mandatory layout, ABI, modules, runtime, CGI upload, OOM and FPM checks.\n' | tee "$RUN/reports/mandatory-checks.txt"

# Keep every raw upstream result; compatibility changes and old fixtures may
# yield failures. Skipped/expected-fail cases are never reported as passes.
cd "$RUN/php-source"
export TEST_PHP_CGI_EXECUTABLE="$DEST/bin/php-cgi" TEST_PHPDBG_EXECUTABLE="$DEST/bin/phpdbg"
run_suite php-phpt "$PHP" -n run-tests.php -n --offline -x tests Zend/tests ext sapi/phpdbg/tests
run_suite opcache-phpt "$PHP" -n run-tests.php -n --offline -x -d "zend_extension=$EXT/opcache.so" -d opcache.enable_cli=1 ext/opcache/tests
else
    printf 'SKIPPED: tests and runtime checks (enable with --with-tests).\n' | tee "$RUN/reports/test-mode.txt"
    for suite in geoip-1.1.1-tests mcrypt-original-runtime "igbinary-$IGBINARY_VERSION-tests" php-phpt opcache-phpt; do
        printf '%s SKIPPED\n' "$suite" >> "$RUN/reports/test-status.txt"
    done
    printf 'SKIPPED: layout, ABI, modules, runtime, CGI upload, OOM and FPM checks.\n' > "$RUN/reports/mandatory-checks.txt"
fi

# Package the full staged tree and reports. This never installs to PREFIX.
cat > "$RUN/reports/READ-ME.txt" <<'REPORT'
PHP 7.2.34 candidate: NOT RELEASE READY; target/application tests pending.
Patches: 0105 multipart limit; 0135 ZSTR_MAX_LEN dependency; 0159 EOL fixes for
CVE-2026-109618 / CVE-2026-109619. All other vendor patches are excluded.
Upload progress is disabled even when INI says On. OOM immediately exits the
worker without PHP shutdown handlers/destructors/session saving.
Sources are hash pinned; patch source DSC is signed by a pinned fingerprint.
Original ionCube (iversion 100203), GeoIP 1.1.1, mcrypt (reported module version
7.2.3) and igbinary 2.0.6RC1 are preserved byte-for-byte from the audited main
copy. Their hashes are checked even without --with-tests; see original-extensions.sha256.
These binaries are downloaded, not rebuilt. The original mcrypt source is not
available; its 7.2.3 module version is not a claimed PECL source release.
GeoIP/igbinary official source archives provide reference PHPT tests only;
mcrypt is checked by original API metadata and a ciphertext captured on main.
With --with-tests, igbinary APC serializer ABI=no, session support=yes,
compact_strings=On and value/session roundtrips are checked. It stays inactive
in the standard profile. See test-mode.txt and test-status.txt for this invocation.
PHP 7.2.34 retains its bundled OPcache 7.2.34, ZIP 1.15.4, SQLite 3.28.0,
timelib/timezone and PEAR packages; these are accepted changes from PHP 7.2.3.
The production library profile uses libcurl3 7.58.0-2ubuntu2 (CURL_OPENSSL_3),
OpenSSL 1.0.2n-1ubuntu5.6 and PNG12 1.2.54-1ubuntu1, extracted privately from
pinned Ubuntu packages. curl headers come from its matching 7.58.0 source.
The private libraries are build/test inputs, not bundled runtime replacements.
Direct ELF dependencies and cURL/OpenSSL symbol versions are checked even when
--with-tests is absent. PNG16 may load indirectly via FreeType, as on production.
Other build-host dependencies remain the pinned Bionic profile; the entire
production OS and every transitive package version have not been reproduced.
These PHP patches do not update or patch the existing system libraries.
GeoIP's original module still reports its compile-time library version 1.6.0.
Matching original .so bytes does not establish identical system-library behavior.
Ubuntu shared libraries are not bundled. Check target ldd/versioned symbols.
Existing php.ini, FPM pools, GeoIP.dat, sockets, PIDs and logs are not included.
Preserve these during a separately reviewed deployment; no deployment was done.
Test execution is optional; SKIPPED does not mean PASS. On a resumed run, older
logs may remain; test-mode.txt and test-status.txt describe this invocation.
When enabled, broad PHPT logs are unmodified. Known categories include disabled upload
progress, OOM diagnostic formatting, absent optional modules, old TLS fixtures,
TTY-dependent tests and GeoIP's old 019 fixture. This new run has NOT had its
individual failures classified automatically: investigate every nonzero suite.
When enabled, mandatory checks exercise synthetic behavior, not every exploit or encoded app.
No blanket security or bit-identical reproducibility claim is made. PHP is EOL.
REPORT
sha256sum "$SCRIPT_PATH" > "$RUN/reports/build-script.sha256"
mkdir "$RUN/stage/release-metadata" "$RUN/artifacts"
cp -a "$RUN/reports" "$RUN/logs" "$RUN/stage/release-metadata/"
(
    cd "$RUN/stage"
    find . -type f ! -path ./SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
    sha256sum --check --status SHA256SUMS
    tar --sort=name --mtime=@1601510400 --owner=0 --group=0 --numeric-owner -cf - . | \
        gzip -n > "$RUN/artifacts/xtream-php-7.2.34.tar.gz"
)
gzip -t "$RUN/artifacts/xtream-php-7.2.34.tar.gz"
(cd "$RUN/artifacts" && sha256sum xtream-php-7.2.34.tar.gz > SHA256SUMS)
printf '\nPHP folder: %s/php/\nArchive: %s/artifacts/xtream-php-7.2.34.tar.gz\nReports: %s/reports/\n' "$RUN" "$RUN" "$RUN"
if ((TEST_FAILURES)); then
    printf 'Candidate created; upstream test suites returned failures. See test-status.txt and logs. Exit 2.\n'
    exit 2
fi
if ((WITH_TESTS)); then
    printf 'Build/tests completed. Target libraries/configuration and application validation are still pending.\n'
else
    printf 'Build/packaging completed. Tests and runtime checks were skipped; enable with --with-tests.\n'
fi
