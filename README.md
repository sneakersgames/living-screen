# OpenDisplay iMac

A small Arch Linux image that turns a 2017 Retina iMac into a screen for a
MacBook, using [OpenDisplay](https://github.com/peetzweg/opendisplay).

- Power on: it boots straight into the OpenDisplay receiver. No desktop, no login.
- Plug a Thunderbolt cable into the MacBook: the panel lights up and the Mac
  extends onto it on its own.
- Unplug, or let the Mac sleep: the panel goes dark a minute later.
- Press **Ctrl+Alt+2** on a keyboard attached to the iMac: it becomes the
  screen of a gaming PC instead, through
  [Moonlight](https://moonlight-stream.org). **Ctrl+Alt+1** returns to the
  Mac. See "Gaming mode" below; this part has not run on a real iMac yet.

The same image is the live USB stick (for testing, nothing is written to the
iMac) and the installer.

**Status: runs on a real iMac18,3 from the live stick.** Confirmed there:
the panel at 5120x2880, hardware H.264 and HEVC decoding, the Thunderbolt
link to an Apple silicon MacBook, and a session started from the Mac's
OpenDisplay menu, and the Mac connecting by itself over the cable when it is
plugged in. Not yet confirmed: the installer on real hardware.

## What is in it

| Piece | What it does |
|---|---|
| `opendisplay-receiver` | Upstream's Linux receiver, built from a release tag |
| `odimac-kiosk.service` | Starts `sway` on tty1 as user `odimac`, at scale 2, with nothing but the receiver in it |
| `mode` | Switches between the three sway workspaces: `display` (the receiver), `game` (Moonlight) and `shell` (a terminal) |
| `odimac-powerd` | Lights the panel while a sender is connected, a cable was just plugged in, or the gaming or terminal mode is showing; darkens it otherwise, optionally suspends |
| `10-odimac-thunderbolt.network` | Link-local addresses on the Thunderbolt link, which is how the Mac recognises a direct cable |
| `odimac-doctor` | Reports on panel, hardware decoding, Thunderbolt and the receiver; runs the suspend test and a decode benchmark |
| `odimac-install` | Copies the live system onto the internal disk |

Everything except the receiver is in the `odimac` package
(`packages/odimac/`). There is no Wi-Fi. Wired Ethernet gets DHCP if you
plug it in, for maintenance and as the path to the gaming PC: a firewall (`odimac-firewall.service`)
makes the receiver reachable and visible over the Thunderbolt cable alone, so
a session can never end up on Wi-Fi by way of the iMac's Ethernet port.
`systemctl disable --now odimac-firewall` lifts that.

## Build

With Docker, on Linux or a Mac:

```bash
./build.sh
```

This produces `out/odimac-<date>-x86_64.iso` and the `odimac` packages.

- **Apple silicon Mac:** the build runs in an emulated x86_64 container. In
  Docker Desktop turn on Settings → General → "Use Rosetta for x86_64/amd64
  emulation". Not tested on Apple silicon yet.
- **First build is slow, later ones are not.** The receiver and the 5K
  driver are compiled once and kept in `out/cache` (as are downloaded
  packages); after that a build only reassembles the image. They are rebuilt
  when what they are made from changes. Delete `out/cache` to start over.
- **Other receiver source:** it is built from upstream tag `v1.30.3`; set
  `OPENDISPLAY_REPO` and `OPENDISPLAY_REF` for a fork or another tag.
- **Without Docker:** the "Build ISO" workflow under the repository's
  Actions tab builds the same image and attaches it to the run.

### Write it to a USB stick

This erases the stick. On macOS, find the stick's disk number first:

```bash
diskutil list external
```

Then, with `N` replaced by that number (`rdiskN`, with the `r`, is much
faster):

```bash
diskutil unmountDisk /dev/diskN
```

```bash
sudo dd if="$(ls out/odimac-*.iso | tail -n1)" of=/dev/rdiskN bs=4m status=progress
```

macOS then says the disk is not readable; choose Eject. On Linux:

```bash
sudo dd if="$(ls out/odimac-*.iso | tail -n1)" of=/dev/sdX bs=4M status=progress oflag=sync
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

## Gaming mode

The iMac can also be the only screen of a Windows PC, for games: the PC
streams its picture over the wired network and the iMac shows it with
Moonlight. Keyboard, mouse and controllers plugged into the iMac are passed
on to the PC.

| Keys | Mode |
|---|---|
| **Ctrl+Alt+1** | The Mac's display (the default) |
| **Ctrl+Alt+2** | Gaming: Moonlight, started on first use |
| **Ctrl+Alt+3** | A terminal on the iMac (user `odimac`); `exit` closes it |

The keys also work during a game. Both modes return to the Mac's display
when their program quits, or after ten minutes without input
(`MODE_IDLE_RETURN`; a running stream does not count as idle). The Mac's
session carries on in the background while another mode is showing.

Set-up, once:

1. On the PC, install [Apollo](https://github.com/ClassicOldSong/Apollo)
   (Sunshine with a built-in virtual display, so the PC needs no monitor of
   its own afterwards) or [Sunshine](https://github.com/LizardByte/Sunshine)
   with an HDMI dummy plug. This step needs a screen on the PC.
2. Connect the iMac's Ethernet port to the same network as the PC.
3. Press Ctrl+Alt+2. In Moonlight choose "Add PC manually" and enter the
   PC's address: Moonlight cannot find the PC by itself, because the firewall
   blocks the discovery protocol that would also show the receiver to Macs on
   the network. Moonlight shows a PIN; enter it in Apollo's web page
   (`https://<PC address>:47990`, from any browser).
4. Optional, on an installed system: set `GAME_HOST` in
   `/etc/odimac/odimac.conf` to the PC's address. Ctrl+Alt+2 then goes
   straight into the stream.

Moonlight starts out at 2560x1440 and 60 frames per second, which is exactly
half the panel in each direction. Its settings and the pairing are kept in
`/var/lib/odimac`, so from the live stick they are lost at power-off.
During a stream, Ctrl+Alt+Shift+S shows Moonlight's statistics and
Ctrl+Alt+Shift+Q ends the stream.

## Install

Running from the stick works indefinitely; streaming is no faster from the
internal disk. Installing gets you a faster and more robust boot (no stick
to fail or fall out), settings in `/etc/odimac/odimac.conf` that survive a
reboot, and a stable identity towards the Mac: the live stick forgets
everything at power-off, including the receiver's ID, so the Mac may treat it
as a new display each time. While the image is still changing, staying on
the stick is simpler, because every new image means a reflash either way.

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
| `RECEIVER_DECODER` | `avdec_h264` | Video decoder; see the comment in the file |
| `RECEIVER_EXTRA_ARGS` | empty | Passed to `od-receiver` |
| `GAME_HOST` | empty | The gaming PC's address; empty opens Moonlight's own interface |
| `GAME_APP` | `Desktop` | What to stream with `GAME_HOST` set |
| `GAME_RESOLUTION`, `GAME_FPS` | `2560x1440`, `60` | Stream size and rate |
| `MODE_IDLE_RETURN` | `600` | Seconds without input before the gaming and terminal modes return to the Mac's display; `0` never |

Compositor overrides, such as another scale, go in
`/etc/odimac/sway.d/*.conf`.

With `SUSPEND_AFTER=0` the iMac never sleeps: with the panel dark it idles,
and always reacts to the cable. Set a value only after the suspend test
showed that the cable wakes it; otherwise a suspended iMac needs its power
button.

Logs: `journalctl -b -t odimac-receiver -t odimac-powerd`. During a session
the journal gets one `load:` line a minute (CPU use, the receiver's share,
temperatures, fan speed); `odimac-doctor load` shows the same live.

## Known limits

- **Native 5120x2880 uses a patched graphics driver** (confirmed working on
  an iMac18,3: `eDP-1` at 5120x2880). Apple drives the 5K panel as two
  2560x2880 halves and the stock `amdgpu` driver only wakes one, giving
  3840x2160. The image pins kernel 7.2.11 and adds the `odimac-amdgpu5k`
  package: `amdgpu` rebuilt with the patch stack from
  [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3)
  (upstream thread drm/amd#4455), which presents both halves as one display.
  See "The 5K driver" below.
- **The stream is H.264, at most 4096x2304.** A native 5K stream also needs
  HEVC in the Linux receiver.
- **Suspend is not usable.** On the iMac18,3 the machine resumes but the
  Thunderbolt and USB controllers do not come back
  (`thunderbolt 0000:07:00.0: not ready after resume; giving up`). Keep
  `SUSPEND_AFTER=0`.
- **No shutdown from the Mac.** Use the power button: a short press shuts
  down cleanly.
- **The stream is not encrypted.** The cable is private, and the firewall
  keeps the receiver off the Ethernet network.
- **About 45 frames per second at "Best" quality**, with 13 to 18 ms from
  capture to display, measured on an iMac18,3 over the cable with an Apple
  silicon MacBook. The MacBook's encoder sets that rate (its log counts the
  frames it skips as `enc↓`), not the iMac: `odimac-doctor decode-bench`
  shows the iMac decoding several times faster.
- **Connecting takes about 20 seconds after the cable is plugged in.** The
  Mac finds the iMac at once but its first few connection attempts time out.
- **No audio, no keyboard or mouse forwarding** from the iMac to the Mac.
- **Gaming mode is untested on the iMac.** Open questions: whether the
  internal speakers work (PipeWire is installed, but the 2017 iMac's audio
  chip may need a driver the image does not have; USB audio should work), and
  how fast the Radeon decodes Moonlight's stream. If the picture lags, choose
  software decoding in Moonlight's settings.
- **Gaming mode does not wake the PC by itself.** Moonlight's menu on the
  PC's tile has "Wake PC" once the PC has been seen running.
- The Mac only connects by itself when the cable appears. If the Mac sender
  is started with the cable already in, pick the iMac from its menu once.

## The 5K driver

`odimac-doctor` says whether it is active and which mode the panel runs.

- **Black or garbled screen with the 5K driver:** at the boot menu (on an
  installed system hold Space while it starts) press `e` and add
  `module_blacklist=amdgpu` to the line. The system then starts on the
  firmware's plain framebuffer without the display session. Log in on the
  console and remove the driver:

  ```bash
  pacman -R odimac-amdgpu5k && mkinitcpio -P
  ```

  The stock driver (3840x2160) is used from the next boot.
- **Half the picture stretched across the panel:** the session power-cycles
  the panel once at start to correct this (`PANEL_POWER_CYCLE`); if it still
  happens, `systemctl restart odimac-kiosk`.
- **Do not upgrade the kernel** (`pacman -Syu` refuses because the driver
  package depends on the exact kernel). The patches support the 7.1 and 7.2
  series only. To build an image with Arch's current kernel and the stock
  driver: `KERNEL_PKGVER=current ./build.sh`.

## Develop

```bash
tests/powerd-test.sh
```

runs the panel and suspend policy against a fake sysfs.

```bash
tests/mode-test.sh
```

runs the sway config and the mode switching in a headless sway, with
terminals standing in for Moonlight and the receiver (needs `sway`, `foot`
and `jq`; skips itself without them). To update an
installed iMac, copy `out/odimac-*.pkg.tar.zst` over and `pacman -U` it.
