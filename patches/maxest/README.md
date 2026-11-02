# Maxest kernel source patch series

Apply in numeric order from the kernel tree root (`patch -p1 < 00xx-*.patch`).
The series is against the pinned GKI `android15-6.6` tree at
`3637f4904cf5`; it implements the ABI-preserving relocations described in
`docs/MAXEST.md`:

- 0001-0006: SYSVIPC and ZSWAP reserve relocations, `all_vm_events` ABI cap.
- 0007-0014: NF_TABLES placement, BRIDGE_NETFILTER hook-array/nf_queue/skb_ext,
  IPVLAN/net_device and netns_ipv4 regroups.
- 0015-0021: cgroup subsystem hiding, fanotify ucount/user_namespace and
  fsnotify union, nft synproxy, blkcg punt fields.

Verified: applying all 21 patches in order to a clean copy reproduces the
patched tree used for the maxest build.
