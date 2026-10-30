#!/usr/bin/env bash
# Build a Nubia Z70 Ultra (NX733J) GKI kernel Image and collect its artifacts.
#
# Usage:
#   KERNEL_SRC=/path/to/gki ./scripts/build-kernel.sh [variant]
#
# Variants (defconfig_fragments in common/BUILD.bazel):
#   stock        []                                               (reference build)
#   sukisu_only  ["sukisu.fragment"]
#   full         ["docker_systemd_v2.fragment", "sukisu.fragment"]
#   docker_only  ["docker_systemd_v2.fragment"]                   (control)
#
# Environment:
#   KERNEL_SRC     Kleaf workspace root (the directory containing common/, tools/bazel)
#   OUT            artifact output directory (default ./out-<variant>)
#   BUILD_NUMBER   kernel build number suffix (default 13944661)
#
# The script temporarily edits common/BUILD.bazel to select the fragment list and
# restores the original file on exit (including on failure). It mirrors the manual
# edit described in docs/BUILDING.md.
set -euo pipefail

VARIANT="${1:-stock}"
KERNEL_SRC="${KERNEL_SRC:-$PWD}"
OUT="${OUT:-$PWD/out-$VARIANT}"
BUILD_NUMBER="${BUILD_NUMBER:-13944661}"

case "$VARIANT" in
  stock)       FRAGMENTS='' ;;
  sukisu_only) FRAGMENTS='"sukisu.fragment"' ;;
  full)        FRAGMENTS='"docker_systemd_v2.fragment", "sukisu.fragment"' ;;
  docker_only) FRAGMENTS='"docker_systemd_v2.fragment"' ;;
  *) echo "unknown variant: $VARIANT (stock|sukisu_only|full|docker_only)" >&2; exit 2 ;;
esac

COMMON="$KERNEL_SRC/common"
BUILD_FILE="$COMMON/BUILD.bazel"
BAZEL="$KERNEL_SRC/tools/bazel"

[ -x "$BAZEL" ] || { echo "not a Kleaf workspace: $BAZEL missing" >&2; exit 1; }
[ -f "$BUILD_FILE" ] || { echo "missing $BUILD_FILE" >&2; exit 1; }

if [ -n "$FRAGMENTS" ]; then
  for f in $(echo "$FRAGMENTS" | tr -d '"' | tr ',' ' '); do
    [ -f "$COMMON/$f" ] || { echo "missing fragment: $COMMON/$f" >&2; exit 1; }
  done
fi

BUILD_BACKUP="$(mktemp)"
cp -p "$BUILD_FILE" "$BUILD_BACKUP"
restore_build_file() {
  cp -p "$BUILD_BACKUP" "$BUILD_FILE"
  rm -f "$BUILD_BACKUP"
}
trap restore_build_file EXIT

python3 - "$BUILD_FILE" "$FRAGMENTS" <<'PY'
import re
import sys

path, fragments = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Locate the kernel_aarch64 block inside define_common_kernels and edit only
# that block. Other targets in the same file have their own fragment lists.
start = next((i for i, l in enumerate(lines)
              if re.match(r'^\s*"kernel_aarch64"\s*:\s*\{\s*$', l)), None)
if start is None:
    sys.exit('could not find the kernel_aarch64 target in BUILD.bazel')
end = next((i for i in range(start + 1, len(lines))
            if re.match(r'^\s*\}\s*,\s*$', lines[i])), None)
if end is None:
    sys.exit('could not find the end of the kernel_aarch64 target')

block = [l for l in lines[start:end]
         if not re.match(r'\s*"defconfig_fragments"\s*:', l)]

if fragments:
    out = []
    inserted = False
    for line in block:
        out.append(line)
        if not inserted and '"kmi_symbol_list_strict_mode":' in line:
            out.append('        "defconfig_fragments": [%s],\n' % fragments)
            inserted = True
    if not inserted:
        sys.exit('could not find kmi_symbol_list_strict_mode in kernel_aarch64')
    block = out

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines[:start] + block + lines[end:])
PY

echo "==> variant: $VARIANT"
echo "==> defconfig_fragments: [${FRAGMENTS}]"
cd "$KERNEL_SRC"
BUILD_NUMBER="$BUILD_NUMBER" "$BAZEL" build --config=android_ci //common:kernel_aarch64

BIN="$KERNEL_SRC/bazel-bin"
mkdir -p "$OUT"
cp -f "$BIN/common/kernel_aarch64/Image" "$OUT/Image"
cp -f "$BIN/common/kernel_aarch64/Module.symvers" "$OUT/Module.symvers"
cp -f "$BIN/common/kernel_aarch64_config/out_dir/.config" "$OUT/config"

echo
echo "artifacts in $OUT:"
(cd "$OUT" && sha256sum Image Module.symvers config && stat -c '%s %n' Image config)
