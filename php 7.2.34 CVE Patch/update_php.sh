#!/usr/bin/env bash
# Place beside php/ in iptv_xtream_codes. Restart services manually after success.
set -Eeuo pipefail
umask 077
usage() {
    cat <<'HELP'
Usage (run inside the installed iptv_xtream_codes directory):
  sudo bash update_php.sh install php_build
  sudo bash update_php.sh install /absolute/path/to/php_build
  sudo bash update_php.sh rollback

Active PHP processes are allowed. The prepared directory replaces php atomically;
running processes keep the old executable until you restart them. Cron is not
changed. Immediately after SUCCESS, run start_services.sh as a SEPARATE command.
Expect PHP requests to fail between the directory switch and service restart: the
new tree contains no old PID/socket files. This is not a zero-downtime update.
Avoid editing configuration files while the backup/candidate is being prepared.

install: read a PHP directory containing bin/, sbin/, lib/ and etc/ directly.
Relative paths are resolved beside this script, regardless of the working directory.
Copy the supplied folder to php_patched; preserve php as php_old; prepare a merged
copy; validate; replace php. Existing php_old/php_patched are never overwritten.
Original *.ini, *.conf, etc/ and GeoIP.dat are retained; uploaded configurations
are ignored. During install, session.upload_progress.enabled is forced Off in
lib/php.ini and php_admin_flag is set off in every discovered FPM pool.
Configuration changes and effective values are checked before replacing php.
The supplied folder is not modified. Finish uploading/editing it before install.
Existing file ownership/modes are restored from the original. New paths use
the original php directory's owner/group and the build's modes.
rollback: restore an independent copy of php_old, removing files added by the
update, including the original configurations (Off changes are not reapplied).
php_old remains available. Stale top-level PID/socket files are omitted.

Both actions require root, Python 3, rsync, standard Ubuntu utilities and Linux
RENAME_EXCHANGE support on the installation filesystem (Ubuntu 18.04 x86_64).
No packages are installed, no databases are touched, no service is started.
An incomplete attempt may leave php_old/php_patched for inspection; do not
delete or overwrite the only rollback copy to retry an installation.
HELP
}
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ ${1:-} != --help && ${1:-} != -h ]] || { usage; exit 0; }
ACTION=${1:-}
case "$ACTION:$#" in install:2|rollback:1) ;; *) usage; exit 1;; esac
((EUID == 0)) || fail 'Run with sudo to preserve ownership and permissions.'
BASE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
LIVE="$BASE/php" OLD="$BASE/php_old" PATCHED="$BASE/php_patched"
[[ -d $LIVE && ! -L $LIVE ]] || fail 'Place this script beside a real php/ directory.'
for tool in python3 rsync cp mv flock ldd timeout; do
    command -v "$tool" >/dev/null || fail "Missing utility: $tool"
done
[[ ! -L $BASE/.php-update.lock ]] || fail 'Lock path must not be a symlink.'
exec 9> "$BASE/.php-update.lock"
flock -n 9 || fail 'Another PHP update is running.'
TMP=$(mktemp -d "$BASE/.php-update.XXXXXXXX")
SWITCHED=0
cleanup() {
    local rc=$?
    trap - ERR
    if ((rc != 0)); then
        if ((SWITCHED == 0)); then
            printf 'UPDATE STOPPED: active php was not replaced. No services were restarted.\n' >&2
        else
            printf 'ERROR AFTER SWITCH: inspect php/php_old before restarting services.\n' >&2
        fi
    fi
    # After an atomic exchange, TMP/next contains the previous live tree.
    # Removing these old names does not terminate processes using old inodes.
    rm -rf -- "$TMP"
    return "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "ERROR at line %s. Services were not restarted; inspect php/php_old before retrying.\n" "$LINENO" >&2' ERR

exchange_dirs() {
    python3 - "$1" "$2" <<'PYEXCHANGE'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
a, b = map(os.fsencode, sys.argv[1:])
# RENAME_EXCHANGE swaps both directory entries in one kernel operation.
args = (ctypes.c_int(-100), ctypes.c_char_p(a),
        ctypes.c_int(-100), ctypes.c_char_p(b), ctypes.c_uint(2))
try:
    renameat2 = libc.renameat2
except AttributeError:
    # Ubuntu 18.04 glibc may lack the wrapper; Linux x86_64 syscall is 316.
    if os.uname().machine != 'x86_64':
        sys.exit('Atomic directory exchange unavailable on this platform.')
    libc.syscall.restype = ctypes.c_long
    result = libc.syscall(ctypes.c_long(316), *args)
else:
    renameat2.restype = ctypes.c_int
    renameat2.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                         ctypes.c_char_p, ctypes.c_uint)
    result = renameat2(*args)
if result != 0:
    error = ctypes.get_errno()
    sys.exit('Atomic exchange failed; active php was not replaced: ' + os.strerror(error))
PYEXCHANGE
}
# Check kernel/filesystem support before preparing a backup or touching php.
mkdir -- "$TMP/exchange-a" "$TMP/exchange-b"
exchange_dirs "$TMP/exchange-a" "$TMP/exchange-b"
rmdir -- "$TMP/exchange-a" "$TMP/exchange-b"

if [[ $ACTION == install ]]; then
    SOURCE=$2
    [[ $SOURCE = /* ]] || SOURCE="$BASE/$SOURCE"
    [[ -d $SOURCE && ! -L $SOURCE ]] || fail "Build folder not found or is a symlink: $SOURCE"
    SOURCE=$(cd -- "$SOURCE" && pwd -P)
    [[ ! -e $OLD && ! -L $OLD && ! -e $PATCHED && ! -L $PATCHED ]] ||
        fail 'php_old or php_patched already exists; refusing to overwrite it.'
    # Do not copy a live/backup tree or a parent containing our temporary directory.
    python3 - "$SOURCE" "$BASE" <<'PY'
import pathlib, sys
source, base = map(pathlib.Path, sys.argv[1:])
if source == base or source in base.parents:
    sys.exit('Build folder must not contain the installation directory.')
for reserved in ('php', 'php_old', 'php_patched'):
    path = base / reserved
    if source == path or path in source.parents:
        sys.exit('Build folder must be separate from php/php_old/php_patched.')
PY
    validate_folder() {
        python3 - "$1" <<'PY'
import os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
for directory in ('bin', 'sbin', 'lib', 'etc'):
    p = root / directory
    if not p.is_dir() or p.is_symlink():
        sys.exit('Build folder must directly contain real bin/, sbin/, lib/ and etc/ directories.')
for base, dirs, files in os.walk(str(root), followlinks=False):
    for name in dirs + files:
        p = pathlib.Path(base) / name
        mode = p.lstat().st_mode
        rel = str(p.relative_to(root))
        if stat.S_ISLNK(mode):
            if rel != 'bin/phar' or os.readlink(str(p)) != 'phar.phar' or not (root / 'bin/phar.phar').is_file():
                sys.exit('Unsupported build symlink: ' + rel)
        elif not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)) or mode & 0o6000:
            sys.exit('Unsupported build file or permissions: ' + rel)
for name in ('bin/php', 'bin/php-cgi', 'bin/phpdbg', 'sbin/php-fpm'):
    p = root / name
    if not p.is_file() or p.is_symlink():
        sys.exit('Missing build executable: ' + name)
    with p.open('rb') as f:
        if f.read(4) != b'\x7fELF':
            sys.exit('Not an ELF executable: ' + name)
print('PASS: PHP folder layout and file types')
PY
    }
    validate_folder "$SOURCE"
    printf 'Copying build folder -> php_patched ...\n'
    cp -a -- "$SOURCE" "$TMP/upload"
    validate_folder "$TMP/upload"
    printf 'Backing up php -> php_old ...\n'
    cp -a -- "$LIVE" "$TMP/backup"
    mv -T -- "$TMP/backup" "$OLD"
    mv -T -- "$TMP/upload" "$PATCHED"
    cp -a -- "$OLD" "$TMP/next"
    # Work only on an independent copy. --inplace retains existing inodes/ACLs.
    rsync -rltc --inplace --no-owner --no-group --no-perms \
        --exclude='*.ini' --exclude='*.conf' --exclude='/etc/' --exclude='/GeoIP.dat' \
        -- "$PATCHED/" "$TMP/next/"
    python3 - "$OLD" "$TMP/next" "$PATCHED" <<'PY'
import os, pathlib, shutil, stat, sys
old, new, patched = map(pathlib.Path, sys.argv[1:])
owner = old.lstat()
paths = [new]
for root, dirs, files in os.walk(str(new), followlinks=False):
    paths.extend(pathlib.Path(root) / n for n in dirs + files)
for dst in paths:
    rel = dst.relative_to(new)
    src = old / rel
    if os.path.lexists(str(src)):
        s = src.lstat()
        if src.is_symlink() and not dst.is_symlink():
            raise ValueError('Original symlink changed type: ' + str(rel))
        os.chown(str(dst), s.st_uid, s.st_gid, follow_symlinks=False)
        if not dst.is_symlink(): shutil.copystat(str(src), str(dst), follow_symlinks=False)
    else:
        os.chown(str(dst), owner.st_uid, owner.st_gid, follow_symlinks=False)
        if not dst.is_symlink():
            os.chmod(str(dst), stat.S_IMODE((patched / rel).lstat().st_mode))
print('PASS: original ownership/modes and server configurations retained')
PY
else
    [[ -d $OLD && ! -L $OLD && -f $OLD/bin/php ]] || fail 'Valid php_old backup not found.'
    printf 'Preparing exact rollback from php_old ...\n'
    cp -a -- "$OLD" "$TMP/next"
fi

NEXT="$TMP/next"
CLEANUP_NOTICE=
# Remove only the empty build placeholder, in the candidate, never in the backup.
if [[ $ACTION == install && -d $NEXT/etc/php-fpm.d && ! -L $NEXT/etc/php-fpm.d ]]; then
    rmdir --ignore-fail-on-non-empty -- "$NEXT/etc/php-fpm.d" ||
        fail 'Could not remove empty etc/php-fpm.d. Active php is unchanged.'
    if [[ ! -d $NEXT/etc/php-fpm.d ]]; then
        CLEANUP_NOTICE='OK: Empty etc/php-fpm.d directory removed.'
    else
        CLEANUP_NOTICE='INFO: etc/php-fpm.d contains files/directories and was preserved.'
    fi
fi
EXT="$NEXT/lib/php/extensions/no-debug-non-zts-20170718"
[[ -f $NEXT/lib/php.ini ]] || fail 'Candidate lib/php.ini is missing (upload it or retain the installed one).'
shopt -s nullglob
configs=("$NEXT/etc/"*.conf)
((${#configs[@]})) || fail 'No candidate FPM configuration files found in etc/.'
if [[ $ACTION == install ]]; then
    printf 'Disabling session upload progress in the candidate configurations ...\n'
    python3 - "$NEXT" "$TMP/config-changes.txt" <<'PYCONFIG'
import collections, pathlib, re, stat, sys

root, report = map(pathlib.Path, sys.argv[1:])
key = 'session.upload_progress.enabled'
marker = '; ADDED BY UPDATE_PHP'
section = re.compile(r'^\s*\[([^\]]+)\]\s*(?:[;#].*)?$')
ini_setting = re.compile(r'^\s*([;#]+\s*)?' + re.escape(key) + r'\s*=\s*(.*)$', re.I)
pool_setting = re.compile(r'^\s*([;#]+\s*)?php_(?:admin_)?(?:flag|value)\s*\[\s*["\x27]?'
                          + re.escape(key) + r'["\x27]?\s*\]\s*=\s*(.*)$', re.I)
messages = []

def code_lines(lines):
    # Do not mistake text inside a multiline quoted value for an INI directive.
    quote = None
    for i, line in enumerate(lines):
        if quote is None:
            yield i, line
            if line.lstrip().startswith((';', '#')):
                continue
        escaped = False
        for ch in line:
            if escaped:
                escaped = False
            elif ch == '\\' and quote is not None:
                escaped = True
            elif ch == quote:
                quote = None
            elif quote is None and ch in ('"', "'"):
                quote = ch
            elif quote is None and ch in (';', '#'):
                break
    if quote is not None:
        raise ValueError('Unterminated quoted configuration value')

def normalize(path, fpm=False):
    # Never follow a configuration symlink out of the independent candidate.
    if any(p.is_symlink() for p in [path] + list(path.parents) if p != root.parent):
        raise ValueError('Configuration symlink is unsupported: ' + str(path))
    if not stat.S_ISREG(path.stat().st_mode):
        raise ValueError('Configuration is not a regular file: ' + str(path))
    original = path.read_bytes()
    bom = b'\xef\xbb\xbf' if original.startswith(b'\xef\xbb\xbf') else b''
    lines = original[len(bom):].decode('utf-8', 'surrogateescape').splitlines(keepends=True)
    newline = '\r\n' if any(l.endswith('\r\n') for l in lines) else '\n'
    contexts = collections.OrderedDict()
    context = None if fpm else 'global'
    if not fpm:
        contexts[context] = {'header': None, 'hits': []}
    pattern = pool_setting if fpm else ini_setting
    for i, line in code_lines(lines):
        header = section.match(line.rstrip('\r\n'))
        if header:
            name = header.group(1).strip().strip('"\x27')
            if fpm:
                context = None if name.lower() == 'global' else name
                if context is not None:
                    contexts.setdefault(context, {'header': i, 'hits': []})
            else:
                # PHP 7.2 keeps the active PATH/HOST hash even after an ordinary
                # section header. A missing global setting must precede them all.
                if name.upper().startswith(('PATH', 'HOST')):
                    context = name
                contexts.setdefault(context, {'header': i, 'hits': []})
            continue
        hit = pattern.match(line.rstrip('\r\n'))
        if hit:
            if context is None:
                if hit.group(1) is None:
                    raise ValueError('PHP pool directive outside a pool: ' + str(path))
                continue
            contexts[context]['hits'].append((i, hit))
    edits, remove, prepend = {}, set(), []
    for name, data in contexts.items():
        hits = data['hits']
        if not fpm and name != 'global' and not hits:
            continue
        directive = ('php_admin_flag[' + key + '] = off') if fpm else (key + ' = Off')
        block = marker + newline + directive + newline
        if hits:
            for i, hit in hits:
                remove.add(i)
                if i > 0 and lines[i-1].strip() in (marker, '##ADDED BY UPDATE_PHP'):
                    remove.add(i-1)
            first = hits[0][0]
            edits[first] = block
            active = [h for _, h in hits if not h.group(1)]
            already_off = (len(hits) == 1 and len(active) == 1
                           and active[0].group(2).split(';', 1)[0].split('#', 1)[0].strip().strip('"\x27').lower()
                           in ('', 'off', '0', 'false', 'no'))
            if fpm:
                already_off = already_off and lines[first].lstrip().startswith('php_admin_flag[')
            status = 'already Off' if already_off else 'set to Off'
            if not active:
                status = 'uncommented and set to Off'
            if len(hits) > 1:
                status += '; duplicate declarations removed'
        elif fpm:
            i = data['header']
            edits[i] = lines[i].rstrip('\r\n') + newline + block
            status = 'added Off'
        else:
            prepend.append('[Session]' + newline + block + newline)
            status = 'added Off'
        label = str(path.relative_to(root)) + (' [' + name + ']' if fpm or name != 'global' else '')
        messages.append('OK: ' + label + ' - ' + status + '.')
    output = ''.join(prepend) + ''.join(edits.get(i, '' if i in remove else line) for i, line in enumerate(lines))
    updated = bom + output.encode('utf-8', 'surrogateescape')
    if updated != original:
        # In-place write only inside the candidate preserves ownership, mode and ACL.
        path.write_bytes(updated)
    return len(contexts) if fpm else 0

try:
    normalize(root / 'lib/php.ini')
    pools = sum(normalize(p, True) for p in sorted((root / 'etc').glob('*.conf')))
    messages.append('INFO: processed {} pool section(s) in the server configurations.'.format(pools))
    report.write_text('\n'.join(messages) + '\n')
except (OSError, ValueError) as error:
    sys.exit('ERROR: configuration update failed: ' + str(error))
PYCONFIG
fi
for binary in "$NEXT/bin/php" "$NEXT/bin/php-cgi" "$NEXT/bin/phpdbg" "$NEXT/sbin/php-fpm" "$EXT/"*.so; do
    if ! ldd "$binary" > "$TMP/ldd.log" 2>&1 || grep -q 'not found' "$TMP/ldd.log"; then
        cat "$TMP/ldd.log" >&2
        fail "Unresolved library for $binary. Active php is unchanged; no APT changes were made."
    fi
done
export PHP_INI_SCAN_DIR=
unset PHPRC || true
timeout 20 "$NEXT/bin/php" -n -r 'echo "PHP ",PHP_VERSION,"\n"; if ($argv[1]==="install" && PHP_VERSION!=="7.2.34") exit(1);' "$ACTION"
timeout 20 "$NEXT/bin/php" -c "$NEXT/lib/php.ini" -d "extension_dir=$EXT" \
    -d "geoip.custom_directory=$NEXT" -r '
foreach (["ionCube Loader","Zend OPcache","geoip","mcrypt"] as $m) {
    if (!extension_loaded($m)) { fwrite(STDERR,"Missing module: $m\n"); exit(1); }
}
if (!geoip_db_avail(GEOIP_COUNTRY_EDITION)) exit(1);
if ($argv[1] === "install") {
    $value = ini_get("session.upload_progress.enabled");
    if ($value === false || !in_array(strtolower($value), ["", "0", "off", "false", "no"], true)) {
        fwrite(STDERR, "ERROR: effective session.upload_progress.enabled is not Off\n"); exit(1);
    }
    echo "PASS: effective INI upload progress is Off\n";
}
echo "PASS: candidate INI, extensions and GeoIP database\n";' "$ACTION"
for config in "${configs[@]}"; do
    # Test the candidate pool, redirecting only the FPM test log into scratch.
    printf 'include = "%s"\n[global]\nerror_log = "%s"\n' \
        "$config" "$TMP/fpm-check.log" > "$TMP/fpm-check.conf"
    if ! timeout 20 "$NEXT/sbin/php-fpm" -tt -p "$LIVE" -c "$NEXT/lib/php.ini" \
        -d "extension_dir=$EXT" -d "geoip.custom_directory=$NEXT" -y "$TMP/fpm-check.conf" \
        > "$TMP/fpm-dump.txt" 2>&1; then
        # A full dump can contain environment secrets; report the failed file only.
        fail "FPM configuration check failed: etc/$(basename -- "$config"). Active php is unchanged."
    fi
    if [[ $ACTION == install ]]; then
        python3 - "$TMP/fpm-dump.txt" "$config" "$TMP/config-changes.txt" <<'PYVERIFY'
import pathlib, re, sys
dump, config, report = map(pathlib.Path, sys.argv[1:])
pools, current = {}, None
for line in dump.read_text(errors='replace').splitlines():
    header = re.search(r'NOTICE:\s*\[([^\]]+)\]\s*$', line)
    if header:
        current = None if header.group(1) == 'global' else header.group(1)
        if current is not None:
            pools.setdefault(current, [])
    value = re.search(r'NOTICE:\s*php_admin_value\[session\.upload_progress\.enabled\]\s*=\s*(.*)$', line)
    if value and current is not None:
        pools[current].append(value.group(1).strip().lower())
if not pools:
    sys.exit('ERROR: No effective FPM pools found in etc/' + config.name)
for pool, values in pools.items():
    if not values or any(v not in ('', '0', 'off', 'false', 'no') for v in values):
        sys.exit('ERROR: Off is not enforced in etc/' + config.name + ' [' + pool + ']; check includes/overrides.')
with report.open('a') as f:
    f.write('PASS: etc/' + config.name + ' - effective admin setting is Off in all ' + str(len(pools)) + ' pool(s).\n')
PYVERIFY
    fi
done
# The backup retains its original runtime files; the restored tree starts fresh.
find "$NEXT" -maxdepth 1 \( -type s -o -name '*.pid' -o -name '*.sock' \) -delete
exchange_dirs "$LIVE" "$NEXT"
SWITCHED=1
if [[ $ACTION == install ]]; then
    cat "$TMP/config-changes.txt"
    printf 'PASS: effective INI and FPM upload-progress settings verified Off before activation.\n'
else
    printf 'INFO: rollback restored original configurations; install-time Off changes were not reapplied.\n'
fi
if [[ -n $CLEANUP_NOTICE ]]; then printf '%s\n' "$CLEANUP_NOTICE"; fi
GREEN= RESET=
if [[ -t 1 ]]; then GREEN=$'\033[1;32m'; RESET=$'\033[0m'; fi
printf '\n%sSUCCESS: %s completed. Original backup: %s%s\n' "$GREEN" "$ACTION" "$OLD" "$RESET"
printf 'RESTART REQUIRED NOW: old PHP processes may still be running; FPM sockets must be recreated.\n'
printf 'Run ./start_services.sh separately with root privileges:\n  cd -- %q\n  sudo bash ./start_services.sh\n' "$BASE"
printf 'Rollback command (then restart services again): sudo bash %q rollback\n' "$BASE/update_php.sh"
