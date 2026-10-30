#!/usr/bin/env python3
"""Compare a kernel Module.symvers against the __versions of .ko files.

Usage: crc_check.py <Module.symvers> <module_dir> [<module_dir> ...]

A module's __versions section contains 64-byte records:
  bytes 0..7   CRC (unsigned long, little-endian; upper 4 bytes are padding)
  bytes 8..63  symbol name (NUL-padded)
Each record says "when I was built, symbol X had CRC C". If the kernel exports X
with a different CRC, the module is rejected at load time (bootloop risk).

Exit code 0 iff every referenced symbol is present with an identical CRC.

The module set must be supplied by the user: stock vendor_dlkm, system_dlkm and
vendor_boot first-stage modules (or a rebuilt set). This script never reads the
device.

Tool selection: set OBJCOPY and NM to clang-r510928's llvm-objcopy/llvm-nm.
If unset, KERNEL_SRC is used to find the pinned prebuilts, then PATH is tried.
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile

REC = 64

KERNEL_SRC = os.environ.get('KERNEL_SRC', '')
PREBUILT_BIN = (
    os.path.join(KERNEL_SRC, 'prebuilts/clang/host/linux-x86/clang-r510928/bin')
    if KERNEL_SRC else ''
)

# GNU objcopy on some hosts has no AArch64 target; prefer LLVM's.
_OBJCOPY_CANDIDATES = [
    os.environ.get('OBJCOPY'),
    os.path.join(PREBUILT_BIN, 'llvm-objcopy') if PREBUILT_BIN else None,
    shutil.which('llvm-objcopy'),
    shutil.which('objcopy'),
]
OBJCOPY = next((p for p in _OBJCOPY_CANDIDATES if p and os.path.exists(p)), 'objcopy')

_NM_CANDIDATES = [
    os.environ.get('NM'),
    os.path.join(PREBUILT_BIN, 'llvm-nm') if PREBUILT_BIN else None,
    shutil.which('llvm-nm'),
    shutil.which('nm'),
]
NM = next((p for p in _NM_CANDIDATES if p and os.path.exists(p)), 'nm')


def module_exports(ko):
    """Names exported by a .ko (__ksymtab_<sym> symbols)."""
    try:
        out = subprocess.run([NM, '--defined-only', ko],
                             capture_output=True, text=True).stdout
    except FileNotFoundError:
        return set()
    names = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        sym = parts[-1]
        for prefix in ('__ksymtab_gpl_', '__ksymtab_'):
            if sym.startswith(prefix):
                names.add(sym[len(prefix):])
                break
    return names


def parse_symvers(path):
    crcs = {}
    with open(path, 'r', errors='replace') as f:
        for line in f:
            parts = line.split()
            if len(parts) < 2:
                continue
            try:
                crc = int(parts[0], 16)
            except ValueError:
                continue
            sym = parts[1]
            crcs[sym] = crc
    return crcs


def versions_section(ko):
    """Return raw __versions bytes, or None if absent."""
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, 'versions.bin')
        r = subprocess.run(
            [OBJCOPY, '--dump-section', '__versions=' + out, ko],
            capture_output=True)
        if r.returncode != 0 or not os.path.exists(out):
            return None
        with open(out, 'rb') as f:
            return f.read()


def parse_versions(raw):
    out = []
    for off in range(0, len(raw) - REC + 1, REC):
        crc = struct.unpack_from('<Q', raw, off)[0]
        name = raw[off + 8: off + REC].split(b'\0', 1)[0].decode('utf-8', 'replace')
        if name:
            out.append((name, crc & 0xffffffff))
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    symvers_path = sys.argv[1]
    dirs = sys.argv[2:]

    symvers = parse_symvers(symvers_path)
    print(f"My kernel: {symvers_path}  ({len(symvers)} exported symbols)")
    print(f"Tools: OBJCOPY={OBJCOPY} NM={NM}")

    mods = []
    for d in dirs:
        for root, _, files in os.walk(d):
            for fn in files:
                if fn.endswith('.ko'):
                    mods.append(os.path.join(root, fn))
    mods.sort()
    print(f"Modules: {len(mods)} across {len(dirs)} dir(s)\n")

    total_syms = 0
    mismatch = []
    absent = []
    no_versions = []
    for ko in mods:
        raw = versions_section(ko)
        if raw is None:
            no_versions.append(ko)
            continue
        for name, want in parse_versions(raw):
            total_syms += 1
            have = symvers.get(name)
            if have is None:
                absent.append((ko, name, want))
            elif have != want:
                mismatch.append((ko, name, want, have))

    # Symbols absent from the kernel may legitimately come from other .ko files.
    providers = set()
    for ko in mods:
        providers |= module_exports(ko)
    absent_missing = [a for a in absent if a[1] not in providers]
    absent_module = len(absent) - len(absent_missing)

    print(f"Checked {total_syms} symbol references from {len(mods)} modules")
    print(f"  kernel CRC mismatches     : {len(mismatch)}")
    print(f"  not in kernel, provided by another module : {absent_module}")
    print(f"  MISSING everywhere (fatal) : {len(absent_missing)}")
    print(f"  no __versions             : {len(no_versions)}")

    for ko, name, want, have in mismatch[:50]:
        print(f"  MISMATCH {os.path.basename(ko)}: {name} wants {want:#010x} have {have:#010x}")
    for ko, name, want in absent_missing[:50]:
        print(f"  MISSING  {os.path.basename(ko)}: {name} (wants {want:#010x})")

    return 0 if not mismatch and not absent_missing else 1


if __name__ == '__main__':
    sys.exit(main())
