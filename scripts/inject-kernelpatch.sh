#!/usr/bin/env bash
# Inject the KernelPatch payload (the SukiSU KPM engine) into a built Image.
#
# CONFIG_KPM=y only builds SukiSU's KPM bridge. The engine is KernelPatch,
# applied to the compiled Image with kptools + kpimg after the build. This step
# is not part of the source patch series; skipping it produces a kernel where
# the manager reports KPM as unsupported.
#
# Usage:
#   KERNEL_IMAGE=/path/Image KPTOOLS=/path/kptools KPIMG=/path/kpimg \
#     SUPERKEY='choose-a-strong-key' ./scripts/inject-kernelpatch.sh /path/Image.kpm
#
# Environment:
#   KERNEL_IMAGE      input kernel Image (required)
#   KPTOOLS           kptools binary (required; pinned sha256 checked)
#   KPIMG             kpimg payload (required; pinned sha256 checked)
#   SUPERKEY          KernelPatch supercall key (required; no default)
#   ALLOW_UNPINNED=1  accept different kptools/kpimg hashes (not recommended)
#
# The pinned pair is from SukiSU_patch commit
# eec45788c9a115e5498040298133336d6b6071dd (KernelPatch fork 0.14.0, 0xe00):
#   kptools-linux a6b912ca964d35427d7fbcd87273abac604970e9746fa0613362be971f07259d
#   kpimg         14fc6564fa092afe4a2293268cd061da64a20f61dc91396a404daf13d053f5ca
# See docs/KPM.md.
set -euo pipefail

: "${KERNEL_IMAGE:?set KERNEL_IMAGE to the Image to patch}"
: "${KPTOOLS:?set KPTOOLS to the kptools binary}"
: "${KPIMG:?set KPIMG to the kpimg payload}"
: "${SUPERKEY:?set SUPERKEY (no default; the recorded builds used 123)}"
OUT="${1:?usage: inject-kernelpatch.sh OUT_IMAGE}"

KPT_SHA=a6b912ca964d35427d7fbcd87273abac604970e9746fa0613362be971f07259d
KPIMG_SHA=14fc6564fa092afe4a2293268cd061da64a20f61dc91396a404daf13d053f5ca

[ -f "$KERNEL_IMAGE" ] || { echo "missing KERNEL_IMAGE: $KERNEL_IMAGE" >&2; exit 2; }
[ -x "$KPTOOLS" ] || { echo "KPTOOLS is not executable: $KPTOOLS" >&2; exit 2; }
[ -f "$KPIMG" ] || { echo "missing KPIMG: $KPIMG" >&2; exit 2; }
[ "$KERNEL_IMAGE" != "$OUT" ] || { echo "OUT_IMAGE must differ from KERNEL_IMAGE" >&2; exit 2; }

if [ "${ALLOW_UNPINNED:-0}" != "1" ]; then
  got_kpt=$(sha256sum "$KPTOOLS" | awk '{print $1}')
  got_img=$(sha256sum "$KPIMG" | awk '{print $1}')
  [ "$got_kpt" = "$KPT_SHA" ] || {
    echo "kptools sha256 mismatch: expected $KPT_SHA, got $got_kpt" >&2
    echo "set ALLOW_UNPINNED=1 only if you have verified another pair" >&2
    exit 3
  }
  [ "$got_img" = "$KPIMG_SHA" ] || {
    echo "kpimg sha256 mismatch: expected $KPIMG_SHA, got $got_img" >&2
    exit 3
  }
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$KPTOOLS" -p -s "$SUPERKEY" -i "$KERNEL_IMAGE" -k "$KPIMG" -o "$OUT" \
  | tee "$work/patch.log"

grep -q '^patched=true$' <("$KPTOOLS" -l -i "$OUT") || {
  echo "kptools did not report patched=true on $OUT" >&2
  exit 4
}

for marker in "KernelPatch Version" "sukisu_kpm_supercall_install" "kpm.load_result"; do
  grep -aq "$marker" "$OUT" || {
    echo "missing payload marker in $OUT: $marker" >&2
    exit 5
  }
done

echo "injected: $OUT"
echo "  size:   $(stat -c %s "$OUT")"
echo "  sha256: $(sha256sum "$OUT" | awk '{print $1}')"
