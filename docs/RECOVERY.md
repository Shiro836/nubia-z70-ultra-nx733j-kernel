# Recovery notes

These are observations from recovering a device after a rejected boot. They are
not a universal procedure. Back up your own partitions first, and treat every
write as destructive.

## Before flashing

- Back up at least the boot partitions (`boot_a`, `boot_b`), `vbmeta`, and the
  GPT of every UFS LUN. Verify the backups by reading them back and comparing
  hashes.
- Keep a copy of the factory GPT pair off the device. Without it, a failed boot
  can leave the slot marked unbootable with no way to clear the record from the
  bootloader.
- Confirm your EDL setup works read-only (for example, `printgpt`) before you
  need it for writing.

## EDL

On the tested unit, `fastboot boot`, `fastboot flash` and `oem edl` were not
usable. EDL was the working write and recovery path:

- USB ID in EDL mode: `05c6:9008`.
- Enter EDL with the device powered off: hold the documented key combination
  while connecting USB.
- Use an EDL client with the correct programmer/loader for your device. Loader
  files are not included in this repository.
- Read the partition table first (`printgpt` in common EDL tools) to confirm the
  LUN and sector layout before writing.

## The slot-unbootable flag

A rejected boot can be recorded as a slot-unbootable attribute in the GPT on
the boot LUN (UFS LUN 4 on the tested device). Symptoms:

- The device does not boot, even after the stock boot partition is restored and
  verified byte for byte.
- Other boot-critical partitions and boot-state partitions match their factory
  contents.
- The bootloader has already marked the slot unbootable; a good boot image alone
  does not clear that record.

Restoring the stock boot partition was not sufficient, and clearing a single
attribute bit was not sufficient either. Restoring the full factory GPT pair
fixed it:

- primary GPT: 6 sectors starting at sector 0 of LUN 4
- backup GPT: 5 sectors starting at `NUM_DISK_SECTORS - 5`

Write both, verify the readback byte for byte, then reset. After the device
boots, the GPT can be read back and compared again against the factory copy.

## Constraints

- Do not use another device's GPT or partition images. GPT contents are
  device-specific.
- Do not write a GPT without first saving the current one.
- A kernel flash does not modify user data, but a failed boot can still leave
  the device unusable until the slot flag is cleared.
- If you do not have a verified factory GPT backup and a working EDL path, do
  not flash a custom kernel.

## Rollback checklist

1. Stock boot image and its sha256.
2. Factory GPT pair (primary and backup), with hashes verified on readback.
3. EDL client + programmer, tested read-only.
4. Device fully powered off before entering EDL, USB connected directly (no hub).

Flashing is at your own risk. No device images, GPT dumps or loader files are
distributed here.
