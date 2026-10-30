#!/usr/bin/env bash
# Build a boot_a image for the NX733J that keeps the stock OEM-signed AVB
# structures (GKI certificate block + chained vbmeta + AVB footer) and replaces
# only the kernel payload.
#
# Usage:
#   STOCK_BOOT_IMG=/path/to/stock_boot_a.img KERNEL_IMAGE=/path/to/Image \
#     ./scripts/build-boot-image.sh /path/to/out_boot.img [label]
#
# Environment:
#   STOCK_BOOT_IMG  your own stock boot_a image (required; never ship it)
#   KERNEL_IMAGE    kernel Image to package (required)
#   KERNEL_SRC      Kleaf workspace root, for tools/mkbootimg (required)
#   MKBOOTIMG       override mkbootimg.py path
#   PART_SIZE       boot partition size (default 100663296)
#   CERT_OFF        OEM GKI certificate block offset in the stock image
#   CERT_LEN        certificate block length (default 16384)
#   VB_OFF          OEM chained vbmeta offset in the stock image
#   VB_LEN          chained vbmeta length (default 2432)
#
# Layout produced:
#   boot header + kernel (4 KiB aligned) || OEM GKI cert block || OEM vbmeta
#   || zeros to partition end - 64 || OEM AVB footer (offsets updated)
#
# This does not forge hashes or signatures. The OEM signatures stay valid; the
# descriptors' hashes become stale, which this bootloader tolerates. See
# docs/AVB.md for the constraints and warnings.
set -euo pipefail

: "${STOCK_BOOT_IMG:?set STOCK_BOOT_IMG to your own stock boot_a image}"
: "${KERNEL_IMAGE:?set KERNEL_IMAGE to the kernel Image}"
: "${KERNEL_SRC:?set KERNEL_SRC to the Kleaf workspace root}"

OUT="${1:?usage: build-boot-image.sh <output.img> [label]}"
LABEL="${2:-boot}"

MKBOOTIMG="${MKBOOTIMG:-$KERNEL_SRC/tools/mkbootimg/mkbootimg.py}"
PART_SIZE="${PART_SIZE:-100663296}"
CERT_OFF="${CERT_OFF:-36601856}"
CERT_LEN="${CERT_LEN:-16384}"
VB_OFF="${VB_OFF:-36618240}"
VB_LEN="${VB_LEN:-2432}"

[ -f "$MKBOOTIMG" ] || { echo "missing mkbootimg: $MKBOOTIMG" >&2; exit 1; }
[ -f "$KERNEL_IMAGE" ] || { echo "missing kernel: $KERNEL_IMAGE" >&2; exit 1; }
[ -f "$STOCK_BOOT_IMG" ] || { echo "missing stock boot image: $STOCK_BOOT_IMG" >&2; exit 1; }

STOCK_SIZE=$(stat -c %s "$STOCK_BOOT_IMG")
if [ "$STOCK_SIZE" -lt "$PART_SIZE" ]; then
  echo "stock boot image is $STOCK_SIZE B, smaller than partition size $PART_SIZE" >&2
  exit 1
fi
if [ "$(dd if="$STOCK_BOOT_IMG" bs=1 skip=$((PART_SIZE - 64)) count=4 status=none)" != "AVBf" ]; then
  echo "no AVB footer at the expected offset in $STOCK_BOOT_IMG" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 "$MKBOOTIMG" \
  --kernel "$KERNEL_IMAGE" --header_version 4 --pagesize 4096 -o "$WORK/base.img"

BASE=$(stat -c %s "$WORK/base.img")
NEW_VB_OFF=$((BASE + CERT_LEN))
echo "[$LABEL] base=$BASE  certs@$NEW_VB_OFF  vbmeta@$NEW_VB_OFF"

dd if="$STOCK_BOOT_IMG" of="$WORK/certs.bin" bs=1 skip="$CERT_OFF" count="$CERT_LEN" status=none
dd if="$STOCK_BOOT_IMG" of="$WORK/vbmeta.bin" bs=1 skip="$VB_OFF" count="$VB_LEN" status=none
dd if="$STOCK_BOOT_IMG" of="$WORK/footer.bin" bs=1 skip=$((PART_SIZE - 64)) count=64 status=none

python3 - "$WORK/footer.bin" "$NEW_VB_OFF" "$VB_LEN" <<'PY'
import struct
import sys

path, vb_off, vb_len = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, 'rb') as f:
    b = bytearray(f.read())
if b[:4] != b'AVBf':
    sys.exit('footer does not start with AVBf')
struct.pack_into('>Q', b, 12, vb_off)       # original_image_size
struct.pack_into('>Q', b, 20, vb_off)       # vbmeta_offset
struct.pack_into('>Q', b, 28, vb_len)       # vbmeta_size
with open(path, 'wb') as f:
    f.write(b)
PY

cat "$WORK/base.img" "$WORK/certs.bin" "$WORK/vbmeta.bin" > "$OUT"
truncate -s $((PART_SIZE - 64)) "$OUT"
cat "$WORK/footer.bin" >> "$OUT"

echo "[$LABEL] built $OUT ($(stat -c %s "$OUT") bytes)"
sha256sum "$OUT"
