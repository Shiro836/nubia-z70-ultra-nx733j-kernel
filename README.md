# Nubia Z70 Ultra (NX733J) kernel recipes

Build recipes, configs, patches and notes for the Android 15 / GKI 6.6.92 kernel
used by the Nubia Z70 Ultra (model NX733J, MyOS16.0.4MR, build
`20260210.135030`).

This repository does not contain kernel sources, vendor sources, built kernels,
boot images, modules, APKs or keys. It contains the deltas and the procedure
needed to rebuild and package the kernel from public sources.

## Scope and status

The stock kernel is a GKI build from the Android common kernel at commit
`3637f4904cf55eb3e7eccb9d747d754a4e199740` (branch `android15-6.6`, build
number `13944661`, kernel release
`6.6.92-android15-8-g3637f4904cf5-ab13944661-4k`). Building that commit with the
pinned toolchain reproduces the stock `Image` byte for byte
(sha256 `11bf8868...`, 36,596,224 bytes), and the built config matches the
device's running config.

Two modified variants are provided:

- **SukiSU only**: stock config plus SukiSU Ultra v4.3.0 as a built-in driver
  (`CONFIG_KSU=y`).
- **Full**: the Docker/systemd fragment plus SukiSU.

A **control** variant (Docker/systemd only, no SukiSU) is also documented. All
three modified kernels were packaged with the OEM-signature-preserving boot
layout and boot-tested on the device.

The modified images are not byte-identical to stock, by construction. Their
compatibility target is the stock vendor module set: the CRC gate reported
0 kernel mismatches and 0 missing symbols across the 680 stock modules for each
variant.

## Prerequisites

- Linux x86_64 host with enough disk for a Kleaf build (tens of GB).
- A Kleaf workspace of the AOSP common kernel at the commit above. The
  `repo` manifest used is the standard `kernel/manifest` `default.xml`
  (`default revision="main-kernel-build-2024"`, superproject
  `kernel/superproject` revision `common-android15-6.6`). The closest
  best-available identifier for the kernel tree is branch `android15-6.6` at
  commit `3637f4904cf5`.
- The pinned toolchain that ships with that Kleaf revision: clang-r510928
  (Android clang 18.0.0, build 11368308), LLD 18, and pahole v1.25 from
  `prebuilts/kernel-build-tools`. Do not substitute host tools.
- Kleaf `build/kernel` at `b5e2a413b0d6b44a66fb6eb352da2ed42c0477f8`.
- Python 3 and `llvm-objcopy` / `llvm-nm` from clang-r510928 for the module CRC
  gate.
- Your own stock `boot_a` image if you want to package a boot image. The
  builder never ships or downloads one.
- Your own stock module set for the CRC gate (`vendor_dlkm`, `system_dlkm`,
  vendor_boot first-stage `lib/modules`).

## Quick start

```bash
# 1. Fetch the kernel tree (example; use your usual repo setup)
repo init -u https://android.googlesource.com/kernel/manifest -b common-android15-6.6
repo sync -c -j8
git -C common checkout 3637f4904cf55eb3e7eccb9d747d754a4e199740

# 2. Integrate SukiSU (for the modified variants)
#    Follow patches/README.md: vendor the driver tree, fix the uapi symlink,
#    apply both patches, copy the fragments into common/.

# 3. Build
KERNEL_SRC="$PWD" ./scripts/build-kernel.sh full
#    or: stock | sukisu_only | docker_only

# 4. Check the artifacts
./scripts/verify-hashes.sh artifacts "$PWD/out-full" full

# 5. Package a boot image with your own stock boot_a
STOCK_BOOT_IMG=/path/to/your/stock_boot_a.img \
KERNEL_IMAGE="$PWD/out-full/Image" \
KERNEL_SRC="$PWD" \
  ./scripts/build-boot-image.sh /path/to/boot.img full
```

The raw build command, if you prefer to drive the tree yourself, is:

```bash
cd <gki-tree>
BUILD_NUMBER=13944661 ./tools/bazel build --config=android_ci //common:kernel_aarch64
```

Artifacts land in `bazel-bin/common/kernel_aarch64/Image`,
`bazel-bin/common/kernel_aarch64/Module.symvers` and
`bazel-bin/common/kernel_aarch64_config/out_dir/.config`.

## Variants

Fragments are selected through `defconfig_fragments` in
`common/BUILD.bazel`.

| Variant | `defconfig_fragments` | Image sha256 | Image size | config sha256 |
|---|---|---|---|---|
| stock | none | `11bf8868967b8f1657f9364afd48e0be2a351736485994fb5efae21aef595896` | 36,596,224 | `f21f8de739dc13dd5af6fda290ab62322968836af5133f4cb32c02c1a4f6ff18` |
| sukisu_only | `["sukisu.fragment"]` | `241945762e191b45a6cce8da07b2505bde9ad0e4d1899bf32fe3e2aaf470f16d` | 36,796,928 | `b3910c8ebb4e87f7070d54aa8f267a57462d2d78b1afc8fc6968593142a9a10c` |
| full | `["docker_systemd_v2.fragment", "sukisu.fragment"]` | `5735e5dd219d159b155557e61379d381baad936bfb03052e6ffb86f202191e11` | 37,059,072 | `d90af3c0424fe651751c00e479e8c500c01b9c857ea4a451894c8d400c089f1e` |
| control | `["docker_systemd_v2.fragment"]` | `22a4275cce10bc8b85ed94aa822b54a6e3f80f87b70c37e177c8d0ca5eb71a2d` | 36,665,856 | `182a72756294b93e89869f98295d9ef8ade0cde919c5ac203078795efdd36675` |

Module compatibility:

| Variant | `Module.symvers` sha256 | exports |
|---|---|---|
| stock | not recorded | not recorded |
| sukisu_only | `5139c8777949c23c5b7ccc5624099bb6d7ead4275f8515df8db81c1c2228d490` | 9,155 |
| full | `e0785b239df0a4123c859fe7939adfe6d048a343098572bb998642fe78d1aca1` | 9,161 |
| control | `e0785b239df0a4123c859fe7939adfe6d048a343098572bb998642fe78d1aca1` | 9,161 |

The SukiSU builds add no exported symbols; `sukisu_only` differs from stock
only by the KSU code/config and the resulting layout, and `full` has the same
`Module.symvers` as the Docker-only control.

### Config fragments

`configs/docker_systemd_v2.fragment` enables the largest Docker/systemd option
set that keeps the stock module ABI intact:

```
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_POSIX_MQUEUE=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_VXLAN=y
CONFIG_UNIX_DIAG=y
```

`CGROUP_NET_CLASSID` and `FANOTIFY` are deliberately absent. They change
kernel-exported CRCs (7,785 and 8,117 mismatches against the stock module set,
respectively) and would break module loading unless the whole module set were
rebuilt. `NF_TABLES` and `BRIDGE_NETFILTER` are also excluded: they alter
`struct sk_buff` and produced 8,263 mismatches in an earlier experiment.

`configs/sukisu.fragment` sets `CONFIG_KSU=y` and `CONFIG_KSU_MANUAL_SU=y` and
leaves KPM, debug and manager-disable options off.

## Reproducing the exact hashes

The hashes above come from the recorded build with the pinned tree and
toolchain. Three details matter:

1. **Module-signing certificate.** The kernel build normally generates a random
   RSA key and embeds its certificate in `Image` (`system_certificate_list`).
   The stock `Image` embeds the OEM/GKI signing certificate. To reproduce the
   stock `Image` exactly, that public certificate is recovered from a stock
   image, combined with a throwaway local RSA-4096 private key (needed only by
   `sign-file` for modules), and injected through a build-only override of
   `certs/Makefile`. Without it, the embedded certificate and the derived
   `build-id` differ. See `docs/BUILDING.md`; never commit the private key.
2. **Tree state.** The stock `Image` requires a pristine `common/` at the pinned
   commit. The modified variants carry an untracked `drivers/kernelsu/` tree, so
   `scripts/setlocalversion` appends `-dirty` to the release string. That is
   expected and is part of the recorded build.
3. **Clean builds after config changes.** Bazel has reused pre-config objects
   after a fragment change. Run a clean build before gating a new config.

The config hashes are independent of the signing certificate.

## Module compatibility gate

The stock kernel must load the stock vendor modules. `scripts/crc_check.py`
compares each module's `__versions` CRCs against the kernel's `Module.symvers`:

```bash
KERNEL_SRC=<gki-tree> python3 -I scripts/crc_check.py \
  <out>/Module.symvers \
  /path/to/vendor_dlkm /path/to/system_dlkm /path/to/vendor_boot/lib/modules
```

Expected result for the recorded variants: 0 kernel CRC mismatches and 0
symbols missing everywhere. The module set is not included here; supply your own
copy from the device or your firmware package. Do not mix stock and rebuilt
modules after a config change: the module set must be self-consistent with the
kernel it will load on.

## Boot image packaging

The NX733J bootloader enforces AVB signatures even when unlocked. Re-signing a
correct image with a local key is rejected, and patching vbmeta flags with an
invalidated signature also fails. What works is keeping the OEM-signed
structures and replacing only the kernel payload:

```
boot header + kernel (4 KiB aligned)
|| OEM GKI certificate block (16,384 B)
|| OEM chained vbmeta (2,432 B)
|| zeros
|| OEM AVB footer (64 B, offsets updated)
```

The partition is 100,663,296 bytes. `scripts/build-boot-image.sh` builds this
layout from your own stock `boot_a`. The recorded boot images (all
boot-tested) are:

| Variant | boot image sha256 |
|---|---|
| sukisu_only | `742ac0987601a36aec428cdf3975a46e1aab56a4f9abfb331359260e8f851158` |
| full | `c9b7834b4b58699456bff49d73511c5cf321f853ecc96fa246223ec58cb7fb6f` |
| control | `3a28356c3e544a804bf1025d44075aee71e4947c1eb067c3f0d797c0295be6b5` |

Read `docs/AVB.md` before packaging anything. The mechanism relies on the
loader tolerating stale descriptor hashes when the signatures are valid; it does
not forge signatures and it does not modify the phone.

## Warnings

- Flashing a kernel can make the device unbootable. Back up your own boot
  partitions and GPT first, and have an EDL recovery path.
- A rejected boot on this platform can be recorded in the GPT slot attributes,
  and restoring the boot partition alone may not clear it. See
  `docs/RECOVERY.md`.
- Never publish OEM-signed stock boot images, dumps, loader files or content
  extracted from a device. The builder requires each user's own stock image.
- `fastboot boot` / `fastboot flash` and `oem edl` were not usable on the tested
  unit; EDL (USB ID `05c6:9008`) was the working write and recovery path.

## Credits

- Android common kernel and Kleaf, AOSP.
- SukiSU Ultra, GPL-2.0.
- ZTE/Nubia for the published kernel source packages (used for the vendor
  module work; not part of this repository).
- `avbtool` from AOSP, Apache-2.0.

## License

The recipes and documentation in this repository are provided under
GPL-2.0; the full text is in `LICENSE`. Components referenced here keep their
own licenses: AOSP tooling is Apache-2.0, SukiSU Ultra is GPL-2.0, and
`avbtool` is Apache-2.0.
