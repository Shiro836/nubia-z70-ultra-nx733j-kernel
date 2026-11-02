# KPM (Kernel Patch Module) on the NX733J build

`CONFIG_KPM=y` is necessary but **not sufficient**. It builds SukiSU Ultra's
KPM bridge (`drivers/kernelsu/extension/kpm/`, supercall ABI v2, the
`sukisu_kpm_supercall_install` path). The KPM engine is **KernelPatch**
(`kpimg`), which is injected into the compiled `Image` with `kptools` after the
kernel build. It is not a source patch and is not part of the maxest series.

If the injection step is skipped, the kernel still contains the bridge, but the
manager reports KPM as unsupported and `ksud kpm version` fails with
`EOPNOTSUPP`. That is exactly what happened to the v2.0 boot image; v2.1 is the
same source build plus this injection step.

## Pinned pair

Both files come from SukiSU_patch commit
`eec45788c9a115e5498040298133336d6b6071dd`:

| Item | URL | SHA-256 |
|---|---|---|
| `kptools-linux` | `https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/eec45788c9a115e5498040298133336d6b6071dd/kpm/kptools-linux` | `a6b912ca964d35427d7fbcd87273abac604970e9746fa0613362be971f07259d` |
| `kpimg` | `https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/eec45788c9a115e5498040298133336d6b6071dd/kpm/kpimg` | `14fc6564fa092afe4a2293268cd061da64a20f61dc91396a404daf13d053f5ca` |

`kpimg` is the SukiSU KernelPatch fork, version `0xe00` (0.14.0), compiled
`20:07:48 Oct 27 2026`, config `android,release`, arch `arm64`. The copy in the
SukiSU v4.3.0 manager APK (`assets/kpm/kpimg`) is byte-identical.

## Build steps

After the kernel build (and after the `Module.symvers` gate):

```bash
KERNEL_IMAGE=/path/to/Image \
KPTOOLS=/path/to/kptools \
KPIMG=/path/to/kpimg \
SUPERKEY='your-supercall-key' \
  ./scripts/inject-kernelpatch.sh /path/to/Image.kpm

STOCK_BOOT_IMG=/path/to/your/stock_boot_a.img \
KERNEL_IMAGE=/path/to/Image.kpm \
  ./scripts/build-boot-image.sh /path/to/boot_kpm.img
```

The recorded builds used superkey `123` (test-only). `SUPERKEY` is
KernelPatch's own supercall key; choose your own and keep it consistent with any
KernelPatch userspace you use.

## Verification

On the host:

- `kptools -l -i Image.kpm` prints `patched=true` and kpimg version `0xe00`.
- The Image contains `KernelPatch Version`, `sukisu_kpm_supercall_install` and
  `kpm.load_result`.
- The diff against the unpatched Image is limited to the ARM64 header fields,
  the kallsyms map-anchor NOP region, and the appended payload.

On the device:

```bash
ksud extension check kpm     # supported
ksud kpm version             # 3584 (20:07:48 Oct 27 2026)
```

`dmesg` shows `KernelSU: extension: registered handler for kpm` and
`[+] KP D get_module_nums: 0` when the bridge queries KPM.

## ABI impact

`kptools` does not touch `__kcrctab` or `__versions` data and does not change
the source build's exported CRCs, vermagic, or release string. The injected
Image is gated with the same `Module.symvers` as the source Image; the 680
stock modules load unchanged.

## Risk

KernelPatch works around kCFI on GKI (`CONFIG_CFI_CLANG=y`). The pinned payload
booted on the tested NX733J with the maxest kernel, but this remains a
post-build binary patch: keep a `boot_a` backup, and keep an EDL recovery path
before flashing.
