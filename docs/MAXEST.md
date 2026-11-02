# Maxest ABI-safe kernel

The maxest build is the largest feature set that keeps the stock vendor module
set loadable: the module CRC gate reports **0 mismatches across all 680 stock
modules** and the kernel exports **0 changed CRCs**. It is a kernel-only
release. The stock vendor modules are expected and load unchanged; module-only
drivers enabled by this config are not part of the kernel release.

It is the recommended build for the NX733J and is prepared for release v2.0.

## Target

| Item | Value |
|---|---|
| Device | Nubia Z70 Ultra, model NX733J, board PQ84A01 |
| Firmware family | MyOS16.0.4MR, build `20260210.135030` |
| Kernel source | AOSP common kernel `android15-6.6`, commit `3637f4904cf55eb3e7eccb9d747d754a4e199740` |
| Kernel release | 6.6.92 |
| Build number | 13944661 |
| Toolchain | clang-r510928 (Android clang 18.0.0, build 11368308), LLD 18, pahole v1.25 |
| Release string | `6.6.92-android15-8-g3637f4904cf5-dirty-ab13944661-4k-forsen` |
| Bootloader | unlocked; OEM AVB signature checks still enforced |

Maxest is built on top of the earlier Docker/systemd, SYSVIPC, ZSWAP,
NF_TABLES, BRIDGE_NETFILTER and IPVLAN work, including SukiSU Ultra v4.3.0,
SUSFS and KPM.

## Features

- **IPC / containers:** SYSVIPC, namespaces (`PID`, `IPC`, `USER`, network),
  POSIX message queues, devtmpfs, VXLAN, UNIX_DIAG, CRIU/checkpoint-restore.
- **Memory:** ZSWAP (LZO/zbud) and ZRAM writeback. ZSWAP is built in but
  disabled at boot unless enabled on the kernel command line or by init.
- **Netfilter:** NF_TABLES core and the built-in `NFT_*` dataplane, including
  SYNPROXY; BRIDGE_NETFILTER; ipset; xt_ADDRTYPE.
- **Networking:** IPVLAN (`=m`, with L3S), Open vSwitch, bonding, team,
  iSCSI, USB/IP, CAKE/PIE/FQ_PIE qdiscs, MACVLAN.
- **Filesystems:** BTRFS (with POSIX ACL), XFS (quota, POSIX ACL), CIFS,
  NFS client and server (NFSv4.1/4.2, NFSDv4), ksmbd, NTFS3, SquashFS, NBD,
  ISO9660, UDF, JFS, ReiserFS, HFS, HFS+, UFS, NILFS2, ROMFS, CRAMFS,
  eCryptfs, OCFS2, GFS2, AFS, Ceph.
- **Cgroups:** devices, pids and net_cls controllers in addition to the stock
  set.
- **Security:** Landlock and Yama LSMs, fanotify, standard Docker/systemd
  isolation options.
- **USB:** serial drivers (option/usb_wwan, pl2303, sierra, CH341, CP210X),
  USB Ethernet (usbnet, cdc_ether, rndis_host, asix, cdc_subset, smsc95xx,
  smsc75xx), USB ACM, uinput, USB audio, UVC, USB gadget RNDIS.
- **Bluetooth:** USB HCI (btusb with Intel/Realtek support).
- **Root/extension:** SukiSU Ultra built in, SUSFS, KPM.

## ABI-preserving techniques

Stock modules embed or size exported kernel types, so the extra features cannot
simply be compiled in. The patch series in `patches/maxest/` keeps the
compiler-visible stock layout for module-facing types by using one of four
patterns:

1. **Existing KABI reserves.** New state that fits an existing
   `ANDROID_KABI_RESERVE` / `ANDROID_BACKPORT_RESERVE` slot is placed there
   (`task_struct` SYSVIPC, `mem_cgroup.zswap_max`, `net_device.l3mdev_ops`,
   the three `netns_ipv4` l3mdev sysctls, `netns_nf.hooks_bridge` pointer).
   The size and offsets do not change.
2. **End-of-structure append.** New fields go after every existing member
   (`struct net` MPLS, `nf_queue_entry`, `tcp_request_sock_ops`,
   `blkcg_gq`, `enum skb_ext_id`, `enum nf_ct_ext_id`). Existing offsets and
   numeric ids do not move.
3. **Existing holes and padding.** NF_TABLES' per-net state goes into the
   alignment hole before `xfrm`; `sock_cgroup_data.classid` uses tail padding.
4. **`__GENKSYMS__` hiding with in-place growth.** For kernel-internal
   structures that modules never allocate or size (`cgroup` arrays,
   `user_namespace.ucount_max`, `fsnotify_group` union, `vm_event_item`), the
   new entries are hidden from genksyms while the compiler grows the
   structure. Exported CRC inputs see the stock declaration.

The result is a kernel whose exported CRCs are unchanged, even though several
kernel-internal structures are larger.

## Recorded layout deltas

These are CRC-neutral because the affected structures are allocated by the
kernel and are not embedded or sized by stock modules. The offsets of all
stock members are preserved.

| Structure | Stock to maxest | Why it is safe |
|---|---|---|
| `net` | 4160 to 4224 | `nft` in an existing hole; `mpls` appended. All 49 stock members keep their offsets; `net` is kernel-allocated. |
| `css_set` / `cgroup` / `cgroup_root` | grow | Fixed arrays sized by `CGROUP_SUBSYS_COUNT`; entries 0..6 keep offsets; kernel-internal. |
| `user_namespace` | 656 to 752 | Real `ucount_max` array appended; an ABI-sized pad preserves `rlimit_max` and the KABI reserves; all other offsets identical. |
| `ucounts` | 144 to 160 | Internal array growth; kernel-allocated, never embedded. |
| `fsnotify_group` | 216 to 312 | The fanotify union is the last member; existing offsets identical. |
| `tcp_request_sock_ops` | 40 to 48 | `cookie_init_seq` appended; existing offsets identical; const kernel object. |
| `nf_ct_ext` | 16 (same) | Id array grows inside padding; existing ids unchanged. |
| `sock_cgroup_data` | 16 (same) | `classid` uses tail padding. |
| `nf_queue_entry` | 88 to 104 | `physin`/`physout` appended; existing offsets identical. |
| `skb_ext` | 8 (same) | `chunks` byte moves; kernel-internal, no stock module uses the skb_ext API. |
| `security_hook_heads` | grows | Kernel-internal LSM hook list (Landlock/Yama). |

## Deliberate exclusions

These were evaluated and left out because they change module-facing layouts or
duplicate stock modules:

- `FUNCTION_TRACER` / `DYNAMIC_FTRACE`: changes `struct module`, which stock
  modules embed.
- `DYNAMIC_DEBUG`: changes `struct ehci_hcd` (debug-only).
- `NF_FLOW_TABLE` / `NFT_FLOW_OFFLOAD`: adds `offload_timeout` to `netns_ct`
  sub-structures mid-structure.
- `IP_VS`: `sk_buff` bitfield plus a `struct net` pointer.
- `MPTCP`: `netns_mib` member and `tcp_sock` / `tcp_request_sock` / `proto`
  fields.
- `SCTP` / `DCCP`: `netns_sctp` / protocol structures.
- `cfg80211` / `mac80211` / `9p` / `hwmon`: already provided by stock modules;
  a built-in copy would duplicate them.
- AppArmor, IMA, EVM and KEXEC: not attempted.
- Rust, bcachefs, NUMA, ACPI, `HZ=1000`: kernel-version or hardware
  constraints.

## Building

1. Check out the pinned GKI tree and toolchain (see `docs/BUILDING.md`).
2. Apply the patch series in `patches/maxest/` (see
   `patches/maxest/APPLY.md`).
3. Copy the fragments from `configs/maxest.fragments/` into
   `<kleaf-workspace>/common/` and list them in the exact order recorded in
   `configs/maxest.fragments/FRAGMENTS.txt` in the `kernel_aarch64`
   `defconfig_fragments`.
4. Build clean:

   ```bash
   cd <kleaf-workspace>
   BUILD_NUMBER=13944661 ./tools/bazel build --config=android_ci //common:kernel_aarch64
   ```

`configs/maxest.config` is the `.config` produced by the recorded build and is
authoritative. The fragments are the reproducible input recipe. The full config
is the reference if the two ever disagree.

Do not use an incremental build after changing fragments. Bazel has reused
pre-config objects in the past; clean or prove every module recompiled before
gating.

## Recorded artifacts and gate

| Artifact | Size | SHA-256 |
|---|---|---|
| Kernel `Image` | 51,915,264 B | `f1f488c6f2d975e4202b054073dbf5ac4f4823d0185bea8373b82e2abe606e82` |
| Built config | 218,830 B | `96e6825461eba8795cd4abc378396259104cb020a99a15fa79e3375902d8c61e` |
| `Module.symvers` | 568,716 B | `3e4befb4681985494c22649bda0669ef2459f15aa109280f70248521cdac7331` |
| OEM-signature boot image | 100,663,296 B | `9f259e8f73e78ebcf5371e68225554dcf1b8aa663da87865fcb6804104457a7e` |

Recorded gate:

- 680 stock modules, 37,116 symbol references.
- 0 kernel CRC mismatches, 0 symbols missing everywhere.
- 9,195 exports: 0 changed CRCs, 34 additive exports.
- Clean build (`BUILD_EXIT=0`), no built-but-undeclared modules.

The gate is against the stock vendor module set. If you change the config,
rebuild the whole module set with the same options and gate it against the new
`Module.symvers`; do not mix stock and rebuilt modules.

## Boot test

The boot image was flashed to `boot_a` on 2026-11-02 and verified
byte-for-byte on readback. It booted: `sys.boot_completed=1`, slot `_a`, 473
modules loaded, SELinux enforcing, wlan/zygote/SurfaceFlinger up, and no
panic/Oops/BUG. The device reported `verifiedbootstate=orange` (unlocked custom
boot). `vbmeta_a` was not modified.

This is a hardware test result for that image and that firmware. It is not a
claim that every unit or firmware revision behaves identically.

## Packaging and rollback

The boot image preserves the OEM GKI certificate block, the chained vbmeta and
the AVB footer, and replaces only the kernel payload. It does not forge
signatures or modify `vbmeta`. See `docs/AVB.md` before packaging or flashing.

Before flashing, back up `boot_a` and the GPT. Keep an EDL recovery path
(USB ID `05c6:9008`). On the tested unit, `fastboot boot` / `fastboot flash`
and `oem edl` were not usable; EDL was the working write and recovery path.
Restoring the boot partition alone may not clear a rejected-boot flag in the
GPT slot attributes; see `docs/RECOVERY.md`.

## Caveats

- **Kernel-only release.** It is tested against the stock vendor module set.
  The module-only drivers enabled by this config (for example USB serial, USB
  Ethernet and USB Bluetooth) are not included; they must be rebuilt against
  this kernel's `Module.symvers` before use.
- **Not byte-identical to stock.** Like every modified variant, it differs from
  the stock `Image` by construction. The hashes above identify the recorded
  artifacts; they are not a claim of full reproducibility.
- **ZSWAP is off by default.** Enable it explicitly if wanted.
- **SUSFS and KPM sources are not vendored.** Follow the SukiSU recipe in
  `patches/README.md` and the fragment comments.
- **Local release string.** `forsen.fragment` sets
  `CONFIG_LOCALVERSION="-4k-forsen"`; this is part of the recorded build.
- **No warranty.** Flashing a kernel can make the device unbootable.
