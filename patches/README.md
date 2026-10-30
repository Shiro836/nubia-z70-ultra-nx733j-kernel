# SukiSU Ultra integration

Two patches integrate SukiSU Ultra v4.3.0 (KSU 41100, tag `e67b14e6`) into the
AOSP GKI tree as a built-in driver (`CONFIG_KSU=y`). They apply in
`<gki-tree>/common/`.

The SukiSU sources themselves are not vendored here. Fetch the pinned tarball
(`sha256 106ff8d1802e493f31bb4a47eedc9e425c363bf2dbed03fa17392500a0561c50`)
from `https://codeload.github.com/SukiSU-Ultra/SukiSU-Ultra/tar.gz/refs/tags/v4.3.0`.

## Order of operations

1. Start from a clean `common/` at ACK commit
   `3637f4904cf55eb3e7eccb9d747d754a4e199740`.

2. Vendor the driver tree and fix the flattened layout. In the commands below,
   `GKI` is the Kleaf workspace root and `RECIPE` is this repository:

   ```bash
   tar xzf SukiSU-Ultra-4.3.0.tar.gz
   cp -a SukiSU-Ultra-4.3.0/kernel "$GKI/common/drivers/kernelsu"
   cp -a SukiSU-Ultra-4.3.0/uapi   "$GKI/common/drivers/kernelsu/uapi"
   ln -sfn ../uapi "$GKI/common/drivers/kernelsu/include/uapi"
   ```

   Upstream keeps `kernel/` and `uapi/` as siblings at the repository root, and
   `kernel/include/uapi` is a symlink to `../../uapi`. After copying `kernel/`
   to `drivers/kernelsu/`, that target resolves to `drivers/uapi` and dangles.
   Copying `uapi/` next to the driver and repointing the symlink to `../uapi`
   restores the same headers with the flattened layout. This is a layout fix,
   not a source change.

3. Apply the integration patch:

   ```bash
   git -C "$GKI/common" apply -p1 "$RECIPE/patches/0001-integrate-sukisu-ultra.patch"
   ```

   It adds exactly:

   - `common/BUILD.bazel`: `"defconfig_fragments": ["docker_systemd_v2.fragment", "sukisu.fragment"],`
   - `common/drivers/Kconfig`: `source "drivers/kernelsu/Kconfig"`
   - `common/drivers/Makefile`: `obj-$(CONFIG_KSU) += kernelsu/`

   The fragment list is variant-dependent; switch it as described in
   `docs/BUILDING.md` or let `scripts/build-kernel.sh` rewrite the line.

4. Pin the version string (no network or git metadata during the build):

   ```bash
   git -C "$GKI/common" apply -p1 "$RECIPE/patches/0002-pin-kernelsu-version.patch"
   ```

   Upstream `Kbuild` queries the GitHub API and git tags at build time. The
   patch replaces that block with:

   ```make
   KSU_VERSION      := 41100
   VERSION_TAG      := 4.3.0
   KSU_VERSION_FULL := v4.3.0-e67b14e6@release
   ```

   This makes the version deterministic and removes the build-time network
   dependency.

5. Copy the fragments:

   ```bash
   cp "$RECIPE/configs/sukisu.fragment" \
      "$RECIPE/configs/docker_systemd_v2.fragment" "$GKI/common/"
   ```

## Notes

- `CONFIG_KSU` is `tristate ... default y` in the driver Kconfig. Sourcing the
  Kconfig therefore enables KSU even without `sukisu.fragment`; the fragment is
  kept for explicitness and pins `CONFIG_KSU_MANUAL_SU` while leaving KPM,
  debug and manager-disable options off.
- The integration adds no exported symbols. `Module.symvers` is unchanged by
  SukiSU in the recorded builds.
- No stock kernel source file other than `BUILD.bazel`, `drivers/Kconfig` and
  `drivers/Makefile` is modified.
