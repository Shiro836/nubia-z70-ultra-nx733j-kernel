# Applying the maxest patch series

The 21 patches in this directory are the kernel-source side of the maxest
build. They implement ABI-preserving relocations so that the extra features can
be enabled without changing any exported symbol CRC. Apply them before building
with `configs/maxest.config` / the `configs/maxest.fragments/` recipe.

Target: AOSP common kernel `android15-6.6` at commit
`3637f4904cf55eb3e7eccb9d747d754a4e199740` (GKI 6.6.92).

## Apply

Run from the kernel tree root, which is `<kleaf-workspace>/common` in a GKI
checkout. The patches use `a/` and `b/` prefixes, so `-p1` strips correctly.
Numeric order matters.

```bash
cd <kleaf-workspace>/common

for p in <recipe>/patches/maxest/[0-9][0-9][0-9][0-9]-*.patch; do
    patch -p1 --forward -i "$p" || exit 1
done
```

A dry run first is recommended:

```bash
for p in <recipe>/patches/maxest/[0-9][0-9][0-9][0-9]-*.patch; do
    patch -p1 --dry-run -i "$p" || exit 1
done
```

No `.rej` or `.orig` files should be produced. If a patch rejects, stop: the
tree or the commit is wrong. Do not hand-merge a rejected hunk without
re-checking the ABI reasoning for that hunk.

The series was verified by applying all 21 patches in order to the 21 pristine
source files they touch and comparing the result with the tree used for the
recorded build; the trees were identical.

## What each group does

The common pattern is: keep the compiler-visible layout that modules were built
against (stock offsets and exported type hashes), and put new state in an
existing KABI reserve, in existing padding, or at the end of an
allocator-owned/kernel-internal structure. `__GENKSYMS__` guards keep genksyms
on the stock declaration while the C compiler sees the new member.

### 0001-0006: SYSVIPC, ZSWAP, vm_events

- `0001`: moves `task_struct.sysvsem` / `sysvshm` into the existing
  `ANDROID_KABI_RESERVE` slots (one 8-byte slot plus a 16-byte union over two
  slots). `sizeof(task_struct)` and all existing offsets are unchanged; the
  genksyms path still sees the plain u64 reserves.
- `0002`: puts `mem_cgroup.zswap_max` in the existing
  `ANDROID_BACKPORT_RESERVE(1)` slot (same size and alignment).
- `0003`-`0006`: hides the ZSWAP `vm_event_item` entries from genksyms,
  defines an ABI-capped `NR_VM_EVENT_ITEMS_ABI`, splits the exported
  `all_vm_events()` (stock buffer size) from an internal
  `all_vm_events_full()` (full size), and switches in-kernel callers
  (`vmstat.c`, s390 appldata) to the full variant.

### 0007-0014: NF_TABLES, BRIDGE_NETFILTER, IPVLAN

- `0007`: places `struct netns_nftables` in the existing 24-byte alignment
  hole between `net.bpf` and `net.xfrm`; the MPLS netns member is appended at
  the end of `struct net` and hidden from genksyms.
- `0008`: appends `SKB_EXT_BRIDGE_NF` at the end of `enum skb_ext_id` so
  existing numeric ids do not move.
- `0009`: appends `nf_queue_entry.physin`/`physout` after the existing
  members.
- `0010`-`0012`: replaces the inline `hooks_bridge[NF_INET_NUMHOOKS]` array in
  `netns_nf` with a pointer stored in the existing KABI reserve (same 8
  bytes), allocates/frees the backing array per netns, and updates the two
  bounds checks to use `NF_INET_NUMHOOKS`.
- `0013`-`0014`: stores `net_device.l3mdev_ops` in an existing KABI reserve
  (same pointer size) and packs the three IPv4 l3mdev sysctls into one 8-byte
  reserve union.

### 0015-0021: cgroups, fanotify, synproxy, blkcg

- `0015`: hides the new `SUBSYS()` entries from genksyms, so
  `CGROUP_SUBSYS_COUNT` hashes at the stock value while the compiler grows the
  fixed arrays in place (entries 0..6 keep their offsets).
- `0016`: appends `sock_cgroup_data.classid` after `prioidx`, using the
  existing tail padding; the size stays 16.
- `0017`: hides the two FANOTIFY `UCOUNT_*` entries, keeps an ABI-sized
  `ucount_max_pad` at the stock position in `user_namespace`, and appends the
  real larger `ucount_max` after `rlimit_max` and the KABI reserves.
- `0018`: hides the fanotify union member in `fsnotify_group`; the union is
  the last member, so existing offsets are preserved.
- `0019`: appends `tcp_request_sock_ops.cookie_init_seq` after the existing
  members.
- `0020`: appends `NF_CT_EXT_SYNPROXY` last in `enum nf_ct_ext_id`, preserving
  existing ids and the `nf_ct_ext` size.
- `0021`: appends the `blkcg_gq.async_bio_*` fields at the end of the
  structure; existing offsets are preserved and the structure is
  kernel-internal.

## Gate before flashing

Build clean, then run the module CRC gate against the exact module set that
will load on the device:

```bash
KERNEL_SRC=<kleaf-workspace> python3 -I <recipe>/scripts/crc_check.py \
  <artifacts>/Module.symvers \
  /path/to/vendor_dlkm /path/to/system_dlkm /path/to/vendor_boot/lib/modules
```

The success criterion is both:

- **0 kernel CRC mismatches** and **0 symbols missing everywhere** across the
  stock module set (680 modules, 37,116 references in the recorded gate).
- A `Module.symvers` diff against the stock-module baseline with **0 changed
  exported CRCs** and only additive exports. The recorded maxest build has
  9,195 exports, 0 changed and 34 additive.

An incremental Bazel rebuild after a config change is not acceptable; clean
first or prove every module recompiled. The full verification procedure and
the exact recorded hashes are in `docs/MAXEST.md`.
