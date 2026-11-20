# OpenDisplay iMac

A small Arch Linux image that turns a 2017 Retina iMac into a screen for a
MacBook, using [OpenDisplay](https://github.com/peetzweg/opendisplay).

- Power on: it boots straight into the OpenDisplay receiver. No desktop, no login.
- Plug a Thunderbolt cable into the MacBook: the panel lights up and the Mac
  extends onto it on its own.
- Unplug, or let the Mac sleep: the panel goes dark a minute later.

The same image is the live USB stick (for testing, nothing is written to the
iMac) and the installer.

**Status: built and tested in a VM; on a real iMac18,3 only the panel mode
and suspend have been checked so far** (see "Known limits"). The Thunderbolt
link and the receiver itself are still unproven on the hardware.

## What is in it

| Piece | What it does |
|---|---|
| `opendisplay-receiver` | Upstream's Linux receiver, built from a release tag |
| `odimac-kiosk.service` | Starts `sway` on tty1 as user `odimac`, at scale 2, with nothing but the receiver in it |
| `odimac-powerd` | Lights the panel while a sender is connected or a cable was just plugged in, darkens it otherwise, optionally suspends |
| `10-odimac-thunderbolt.network` | Link-local addresses on the Thunderbolt link, which is how the Mac recognises a direct cable |
| `odimac-doctor` | Reports on panel, hardware decoding, Thunderbolt and the receiver; runs the suspend test |
| `odimac-install` | Copies the live system onto the internal disk |

Everything except the receiver is in the `odimac` package
(`packages/odimac/`). There is no Wi-Fi and no firewall. Wired Ethernet gets
DHCP if you plug it in, for maintenance.

## Build

On any x86_64 machine with Docker:

```bash
./build.sh
```

This produces `out/odimac-<date>-x86_64.iso` (and the two packages). It
builds the receiver from upstream tag `v1.30.3`; to build a fork or another
tag, set `OPENDISPLAY_REPO` and `OPENDISPLAY_REF`.

Write it to a USB stick (this erases the stick; replace `/dev/sdX`):

```bash
sudo dd if=out/odimac-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Test on the iMac

Hold **Option** while powering on and choose **EFI Boot**. The iMac's disk
is not touched. The screen goes black once the receiver is up; that is the
idle state.

1. On the MacBook, start OpenDisplay and plug in a Thunderbolt 3 cable (a
   real Thunderbolt cable, not a USB-C charging cable). The Mac should
   connect within about ten seconds.
2. If it does not, press **Ctrl+Alt+F2** on a keyboard attached to the iMac
   for a root shell and run:

   ```bash
   odimac-doctor
   ```

   It names the failing layer: no 5120x2880 mode, no hardware H.264 decoder,
   no Thunderbolt controller, no cable link, or the receiver not listening.
3. Check suspend and wake on plug-in, which decides how the iMac idles:

   ```bash
   odimac-doctor suspend-test
   ```

## Install

From the root shell on the live stick:

```bash
lsblk -d
```

```bash
odimac-install /dev/nvme0n1
```

This **erases the whole disk**, macOS included, after asking you to retype
the disk path. Options: `--hostname NAME`, `--ssh-key FILE` (enables ssh for
root with that public key), `--no-password` (locks the root account: no local login).

An iMac with a Fusion Drive shows two disks; install onto the SSD.

## Settings

`/etc/odimac/odimac.conf`, then `systemctl restart odimac-kiosk`:

| Setting | Default | |
|---|---|---|
| `RECEIVER_NAME` | hostname | Name in the Mac's OpenDisplay menu |
| `PANEL_OFF_DELAY` | `60` | Seconds the panel stays lit without a sender |
| `SUSPEND_AFTER` | `0` | Seconds without cable and session before suspending; `0` never suspends |
| `BRIGHTNESS` | unset | Panel brightness in percent, if the kernel offers backlight control |
| `RECEIVER_DEVICE` | `Mac` | See the comment in the file |
| `RECEIVER_EXTRA_ARGS` | empty | Passed to `od-receiver` |

Compositor overrides, such as another scale, go in
`/etc/odimac/sway.d/*.conf`.

With `SUSPEND_AFTER=0` the iMac never sleeps: with the panel dark it idles,
and always reacts to the cable. Set a value only after the suspend test
showed that the cable wakes it; otherwise a suspended iMac needs its power
button.

Logs: `journalctl -b -t odimac-receiver -t odimac-powerd`.

## Known limits

- **The panel runs at 3840x2160, not 5120x2880** (confirmed on an iMac18,3
  with kernel 7.2.11). Apple drives the 5K panel as two 2560x2880 halves and
  the stock `amdgpu` driver only wakes one link, so the panel's own scaler
  stretches a 4K picture. Community kernel patches fix this
  ([taprobane99/iMac5KLinux](https://github.com/taprobane99/iMac5KLinux),
  [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3),
  upstream thread drm/amd#4455); they are not in this image yet.
- **The stream is H.264, at most 4096x2304.** A native 5K stream also needs
  HEVC in the Linux receiver.
- **Suspend is not usable.** On the iMac18,3 the machine resumes but the
  Thunderbolt and USB controllers do not come back
  (`thunderbolt 0000:07:00.0: not ready after resume; giving up`). Keep
  `SUSPEND_AFTER=0`.
- **No shutdown from the Mac.** Use the power button: a short press shuts
  down cleanly.
- **The stream is not encrypted.** The cable is private; if you also plug in
  Ethernet, the receiver is reachable from that network.
- **No audio, no keyboard or mouse forwarding** from the iMac to the Mac.
- The Mac only connects by itself when the cable appears. If the Mac sender
  is started with the cable already in, pick the iMac from its menu once.

## Develop

```bash
tests/powerd-test.sh
```

runs the panel and suspend policy against a fake sysfs. To update an
installed iMac, copy `out/odimac-*.pkg.tar.zst` over and `pacman -U` it.
