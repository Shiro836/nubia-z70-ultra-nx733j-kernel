# AVB on the NX733J

The NX733J bootloader enforces Android Verified Boot signatures even when the
device reports an unlocked bootloader (`secure: yes`). This constrains how a
modified kernel can be packaged.

## Observed behaviour

- A structurally correct boot image re-signed with a locally generated key was
  rejected and dropped to fastboot.
- A vbmeta image patched to disable verification (`flags=3`) with an invalidated
  signature also failed to boot.
- Hash mismatches with valid OEM signatures are tolerated. A Magisk-patched
  `init_boot` (different hash, original signature chain) boots on this device.

The consequence: you cannot re-sign the kernel with your own key, but you can
replace the kernel payload inside a boot image whose OEM AVB structures remain
untouched.

## Stock boot layout

The stock `boot_a` is a kernel-only boot image (header v4, empty ramdisk) on a
100,663,296-byte partition:

| Region | Offset | Length |
|---|---|---|
| Boot header (v4) | 0 | 4,096 (one page) |
| Kernel `Image` | 4,096 | kernel size |
| OEM GKI certificate block | 0x22E8000 (36,601,856) | 16,384 |
| OEM chained vbmeta | 0x22EC000 (36,618,240) | 2,432 |
| AVB footer | partition end - 64 | 64 |

The certificate block contains two vbmeta certificates (`boot` and
`generic_kernel`, salt `d00df00d`) signed with the GKI release key. The chained
vbmeta is signed with the platform key. Public key fingerprints (SHA-1 of the
public key, not private keys):

- platform / device key: `c0b5900ac98072a4a521d50c85af4c8b8a9e6449`
- GKI certificate key: `b42c87bedcf600d7bebe3dbade2444e9724c3159`

## Working layout

Keep every OEM-signed AVB structure and replace only the kernel:

```
boot header + kernel (4 KiB aligned)
|| OEM GKI certificate block (16,384 B, copied from the stock boot image)
|| OEM chained vbmeta (2,432 B, copied from the stock boot image)
|| zero padding
|| OEM AVB footer (64 B, original_image_size and vbmeta_offset updated)
```

The footer's `original_image_size` and `vbmeta_offset` fields are set to the new
vbmeta offset, and `vbmeta_size` to 2,432. The signatures remain cryptographically
valid; only the descriptors' hashes are stale, which this loader tolerates.

`scripts/build-boot-image.sh` implements this layout:

```bash
STOCK_BOOT_IMG=/path/to/your/stock_boot_a.img \
KERNEL_IMAGE=/path/to/Image \
KERNEL_SRC=/path/to/gki \
  ./scripts/build-boot-image.sh /path/to/boot.img full
```

It requires your own stock `boot_a` and never downloads or embeds a stock image.
The offsets and partition size are overridable through the environment
(`PART_SIZE`, `CERT_OFF`, `CERT_LEN`, `VB_OFF`, `VB_LEN`), but the defaults match
this device.

The recorded boot images built with this recipe are boot-tested:

| Variant | sha256 | kernel `Image` |
|---|---|---|
| SukiSU only | `742ac0987601a36aec428cdf3975a46e1aab56a4f9abfb331359260e8f851158` | `24194576...` |
| Full (Docker + SukiSU) | `c9b7834b4b58699456bff49d73511c5cf321f853ecc96fa246223ec58cb7fb6f` | `5735e5dd...` |
| Control (Docker only) | `3a28356c3e544a804bf1025d44075aee71e4947c1eb067c3f0d797c0295be6b5` | `22a4275c...` |

## Constraints and warnings

- You must use your own stock `boot_a`. Do not publish OEM-signed stock boot
  images, dumps or loader files.
- The OEM private keys are not available. This recipe does not forge signatures;
  it preserves them and relies on the loader accepting stale descriptor hashes.
- A wrong offset, footer field or partition size can make the device unbootable.
  Verify the built image size is exactly 100,663,296 bytes and that the footer
  starts with `AVBf`.
- Flashing is at your own risk. Have a verified rollback and an EDL recovery
  path before writing anything. See `docs/RECOVERY.md`.
- On the tested unit, `fastboot boot`, `fastboot flash` and `oem edl` were not
  usable; EDL (USB ID `05c6:9008`) was the working write path.
- This is a device-specific boot mechanism, not a general AVB bypass.

## Rejected alternatives

These were tested and did not boot:

- Generating GKI certificates and an AVB footer with a local key
  (`SHA256_RSA4096`, salt `d00df00d`, rollback index from the stock image).
- Editing vbmeta flags to `3` without a valid signature.

Do not use either as a starting point.
