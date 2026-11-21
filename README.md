# OpenDisplay iMac

A small Arch Linux image that turns a 2017 Retina iMac into three things,
one key press apart:

| Keys | Environment | |
|---|---|---|
| **Ctrl+Alt+1** | Mac display | The screen of a MacBook over a Thunderbolt cable, using [OpenDisplay](https://github.com/peetzweg/opendisplay). The default. |
| **Ctrl+Alt+2** | Gaming | The screen of a Windows PC, streamed over the wired network with [Moonlight](https://moonlight-stream.org) |
| **Ctrl+Alt+3** | Desktop | Arch Linux itself: [Hyprland](https://hypr.land) with a [Quickshell](https://quickshell.org) bar |

The keys are pressed on a keyboard attached to the iMac and work everywhere,
also during a game. They are the **number keys**: Ctrl+Alt+F1, F2 and F3 are
something else (Linux's virtual terminals; F2 is a console, and F1 returns
from it, after which the number keys work again). **Ctrl+Alt+4** opens a
bare terminal, for when the desktop does not start.

The keyboard's brightness and volume keys work in all three, and act on the
iMac.

- Power on: it boots straight into the Mac display. No desktop, no login.
- Plug a Thunderbolt cable into the MacBook: the panel lights up and the Mac
  extends onto it on its own.
- Unplug, or let the Mac sleep: the panel goes dark a minute later.
- Gaming and the desktop start the first time their keys are pressed and
  keep running in the background afterwards. Both return to the Mac display
  after ten minutes without input.

The same image is the live USB stick (for testing, nothing is written to the
iMac) and the installer.

## Status

Runs on a real iMac18,3 from the live stick.

| | |
|---|---|
| Panel at 5120x2880 (patched driver) | confirmed |
| Thunderbolt link to an Apple silicon MacBook, connecting by itself on plug-in | confirmed |
| Mac display, H.264 at 4096x2304 | confirmed, about 45 frames per second |
| Mac display, HEVC at native 5120x2880 | **not tested on the iMac** |
| Gaming, picture and input | confirmed with Apollo on the PC |
| Brightness | confirmed |
| Sound from the speakers | confirmed |
| Desktop (Hyprland, the bar, switching to and from it) | confirmed; Firefox, the file manager and the Omarchy keys are new |
| Installer | **not tested on the iMac** |
| Suspend | does not work, see "Known limits" |

## What is in it

| Piece | What it does |
|---|---|
| `opendisplay-receiver` | Upstream's Linux receiver, built from a release tag |
| `odimac-kiosk.service` | Starts `sway` on tty1 as user `odimac`, at scale 2, with nothing but the receiver in it |
| `mode` | Switches between the environments: `display` (the receiver), `game` (Moonlight) and `shell` (a terminal) are workspaces of that sway; `desktop` is a session of its own |
| `odimac-desktop.service` | The desktop: Hyprland (`hyprland.lua`) and the Quickshell bar (`shell.qml`) on tty3, as the same user, started by Ctrl+Alt+3 |
| `odimac-powerd` | Lights the panel while a sender is connected, a cable was just plugged in, or another environment than the Mac display is showing; darkens it otherwise, optionally suspends |
| `10-odimac-thunderbolt.network` | Link-local addresses on the Thunderbolt link, which is how the Mac recognises a direct cable |
| `odimac-doctor` | Reports on panel, hardware decoding, Thunderbolt and the receiver; runs the suspend test and a decode benchmark |
| `odimac-install` | Copies the live system onto the internal disk |

| `odimac-cs8409` | Sound driver for the iMac's audio chip, which the kernel's own driver cannot play through |

Everything except the receiver and the two drivers is in the `odimac` package
(`packages/odimac/`). There is no Wi-Fi. Wired Ethernet gets DHCP if you
plug it in: it is the path to the gaming PC and the desktop's internet
connection. A firewall (`odimac-firewall.service`)
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
  emulation".
- **First build is slow, later ones are not.** The receiver and the 5K
  driver are compiled once and kept in `out/cache` (as are downloaded
  packages); after that a build only reassembles the image. They are rebuilt
  when what they are made from changes. Delete `out/cache` to start over.
- **The sound driver** is compiled the same way and cached; it takes a
  minute.
- **Other receiver source:** it is built from upstream tag `v1.30.3` plus
  the patches in `patches/opendisplay`; set `OPENDISPLAY_REPO` and
  `OPENDISPLAY_REF` for a fork or another tag, and `OPENDISPLAY_PATCHES=0`
  to leave the patches out.
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

## Gaming

The iMac can also be the only screen of a Windows PC, for games: the PC
streams its picture over the wired network and the iMac shows it with
Moonlight. Keyboard, mouse and controllers plugged into the iMac are passed
on to the PC.

Ctrl+Alt+2 starts Moonlight on first use. It returns to the Mac display when
Moonlight quits, or after ten minutes without input (`MODE_IDLE_RETURN`; a
running stream does not count as idle). The Mac's session carries on in the
background while another environment is showing.

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

## Desktop

Ctrl+Alt+3 starts Hyprland with a bar across the top: workspaces, the
focused window's title, buttons for the other two environments, volume
(click mutes, the scroll wheel changes it) and the clock. The picture is
2560x1440 at scale 2, as on the Mac display.

| Keys | |
|---|---|
| **Cmd+Return** | Terminal |
| **Cmd+Space** | Program launcher |
| **Cmd+Shift+B** | Firefox |
| **Cmd+Shift+F** | Files (Nautilus) |
| **Cmd+W** or **Cmd+Q** | Close the window |
| **Cmd+1** … **0**, **Cmd+Shift+1** … **0** | Go to a workspace, move the window there |
| **Cmd+Tab**, **Cmd+Shift+Tab** | Next, previous workspace |
| **Cmd+arrows**, **Cmd+Shift+arrows** | Focus another window, swap the window with its neighbour |
| **Alt+Tab** | Next window |
| **Cmd+F**, **Cmd+Alt+F** | Full screen, full width |
| **Cmd+T** | Floating or tiled |
| **Cmd+J** | Turn the split between two windows |
| **Cmd+−**, **Cmd+=** | Narrower, wider (with Shift: shorter, taller) |
| **Cmd+G** | Group windows as tabs (**Cmd+Alt+Tab** goes through them) |
| **Cmd+S** | Scratchpad: a workspace that slides over the others |
| **Cmd+Shift+E** | Log out: closes every program and returns to the Mac display |

Windows can also be moved and resized with the mouse: Cmd and the left or
right button, or by their borders. The keys and the look are
[Omarchy](https://omarchy.org)'s, without its menus and themes; Firefox,
Files and Terminal also have buttons in the bar.

Cmd is the Windows key on a PC keyboard.

- **Leaving and coming back.** Ctrl+Alt+1 and Ctrl+Alt+2 leave the desktop
  running with its programs open; Ctrl+Alt+3 brings it back as it was. After
  ten minutes without input it returns to the Mac display by itself
  (`MODE_IDLE_RETURN`; a playing video does not count as idle), and the panel
  goes dark a minute later if no Mac is connected.
- **Who you are.** The desktop runs as the appliance's user `odimac`, with
  its home in `/var/lib/odimac`. That user has no password; `sudo` asks for
  root's, which is the one set during installation and is empty on the live
  stick (press Enter).
- **Installing software.** Firefox and a file manager are there. For
  anything else, with Ethernet plugged in:

  ```bash
  sudo pacman -Sy vlc
  ```

  `sudo pacman -Syu` updates everything except the kernel, which is pinned
  for the 5K driver. On the live stick, installed software and every other
  change is held in memory (half of it at most) and is gone at power-off.
- **Your own settings.** `~/.config/hypr/odimac.lua` is read after the
  shipped configuration (`/usr/share/odimac/hyprland.lua`) and can change
  anything in it. Hyprland is configured in Lua these days; see
  [its wiki](https://wiki.hypr.land/configuring/). The bar is
  `/usr/share/odimac/quickshell/shell.qml`.
- **If it does not start,** Ctrl+Alt+3 falls back to the Mac display. The
  reason is in `journalctl -b -u odimac-desktop`, and Hyprland's own log in
  `/run/user/*/hypr/*/hyprland.log`.

The desktop is a second compositor on its own virtual terminal (tty3) beside
the kiosk session on tty1, so Ctrl+Alt+F1 and Ctrl+Alt+F3 also switch between
them. Ctrl+Alt+F2 is the console login.

## Install

Running from the stick works indefinitely; streaming is no faster from the
internal disk. Installing gets you a faster and more robust boot (no stick
to fail or fall out), settings in `/etc/odimac/odimac.conf` that survive a
reboot, and a stable identity towards the Mac: the live stick forgets
everything at power-off, including the receiver's ID, so the Mac may treat it
as a new display each time. While the image is still changing, staying on
the stick is simpler, because every new image means a reflash either way.

From the console of the live stick (Ctrl+Alt+F2), find the internal disk:

```bash
lsblk -d
```

Then install onto it, with your own time zone:

```bash
odimac-install --timezone Europe/Brussels /dev/nvme0n1
```

This **erases the whole disk**, macOS and its recovery system included,
after asking you to retype the disk path; there is no way back to macOS
afterwards short of Apple's internet recovery (Option+Cmd+R at power-on).
It then asks for a password for root, which is also what `sudo` asks for on
the desktop. When it has finished, pull the stick and restart with
`reboot`.

Options: `--hostname NAME`, `--timezone ZONE` (without it the clock shows
UTC; `timedatectl set-timezone` changes it later), `--ssh-key FILE` (enables
ssh for root with that public key), `--no-password` (locks the root account:
no console login and no `sudo`).

An iMac with a Fusion Drive shows two disks; install onto the SSD.

## Settings

`/etc/odimac/odimac.conf`, then `systemctl restart odimac-kiosk`:

| Setting | Default | |
|---|---|---|
| `RECEIVER_NAME` | hostname | Name in the Mac's OpenDisplay menu |
| `PANEL_OFF_DELAY` | `60` | Seconds the panel stays lit without a sender |
| `SUSPEND_AFTER` | `0` | Seconds without cable and session before suspending; `0` never suspends |
| `BRIGHTNESS` | unset | Panel brightness in percent at start; the keyboard's brightness keys change it afterwards |
| `RECEIVER_DEVICE` | `Mac` | See the comment in the file |
| `RECEIVER_DECODER` | `avdec_h264` | Video decoder; see the comment in the file |
| `RECEIVER_HEVC` | `1` | Offer HEVC, for a native 5K stream; `0` for H.264 at 4096x2304 |
| `RECEIVER_EXTRA_ARGS` | empty | Passed to `od-receiver` |
| `GAME_HOST` | empty | The gaming PC's address; empty opens Moonlight's own interface |
| `GAME_APP` | `Desktop` | What to stream with `GAME_HOST` set |
| `GAME_RESOLUTION`, `GAME_FPS` | `2560x1440`, `60` | Stream size and rate |
| `MODE_IDLE_RETURN` | `600` | Seconds without input before gaming, the desktop and the terminal return to the Mac display; `0` never |
| `PANEL_POWER_CYCLE` | `auto` | See "The 5K driver" |

Overrides for the kiosk's compositor, such as another scale, go in
`/etc/odimac/sway.d/*.conf`; for the desktop's, in
`~/.config/hypr/odimac.lua`.

With `SUSPEND_AFTER=0` the iMac never sleeps: with the panel dark it idles,
and always reacts to the cable. Set a value only after the suspend test
showed that the cable wakes it; otherwise a suspended iMac needs its power
button.

Logs: `journalctl -b -t odimac-receiver -t odimac-powerd -t odimac-mode`. During a session
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
- **Native 5K stream (HEVC) is new and untested on hardware.** The receiver
  is built with `patches/opendisplay/0001-linux-receiver-hevc.patch`, which
  makes it decode HEVC and offer it to the Mac. An Apple silicon Mac then
  sends 5120x2880 instead of H.264 at 4096x2304. Tested here with a test
  sender at 1280x720 only. `RECEIVER_HEVC=0` goes back to H.264.
- **Suspend is not usable.** On the iMac18,3 the machine resumes but the
  Thunderbolt and USB controllers do not come back
  (`thunderbolt 0000:07:00.0: not ready after resume; giving up`). Keep
  `SUSPEND_AFTER=0`.
- **No shutdown from the Mac.** Use the power button: a short press shuts
  down cleanly.
- **The stream is not encrypted.** The cable is private, and the firewall
  keeps the receiver off the Ethernet network.
- **Frame rate is set by the MacBook's encoder**, not the iMac (its log
  counts the frames it skips as `enc↓`). Measured on an iMac18,3 over the
  cable with an Apple silicon MacBook at "Best": about 45 frames per second
  with H.264 at 4096x2304, 13 to 18 ms from capture to display. OpenDisplay's
  own figure for HEVC at 5120x2880 is about 30.
- **Connecting takes about 20 seconds after the cable is plugged in.** The
  Mac finds the iMac at once but its first few connection attempts time out.
- **No audio, no keyboard or mouse forwarding** from the iMac to the Mac.
- **No Wi-Fi and no Bluetooth set-up**, on the desktop either.
- **Sound needs its own driver.** The 2017 iMac's audio chip (Cirrus
  CS8409 with a CS42L83) gets no sound out of the kernel's own driver. The
  image adds the `odimac-cs8409` package: the driver from
  [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio),
  built for the pinned kernel. `odimac-doctor` has a "Sound" section.
- **Gaming: how fast the Radeon decodes Moonlight's stream is not
  measured.** If the picture lags, choose software decoding in Moonlight's
  settings.
- **A soft or blocky picture for a moment, about once a minute,** on the Mac
  display is the Mac's encoder starting a new key frame within its bit rate
  (18 Mbit/s at "Best"). It is not a sign of an overloaded Mac or iMac. At
  irregular moments it is a recovery after a lost frame instead: the
  receiver's `stats` lines in the journal count those as `stalls`.
- **Gaming does not wake the PC by itself.** Moonlight's menu on the
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
- **Half the picture stretched across the panel:** the kiosk session and
  the desktop each power-cycle the panel once when they start to correct
  this (`PANEL_POWER_CYCLE`); if it still happens, `systemctl restart
  odimac-kiosk`, or on the desktop log out (Cmd+Shift+E) and press Ctrl+Alt+3
  again.
- **The kernel stays as it is.** The image's `pacman.conf` leaves `linux`
  out of `pacman -Syu` (`IgnorePkg`), because the driver package fits one
  exact kernel. The patches support the 7.1 and 7.2 series only. To build an image with Arch's current kernel and the stock
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
terminals standing in for Moonlight and the receiver and stubs for the
desktop's service (needs `sway`, `foot` and `jq`; skips itself without
them).

```bash
tests/desktop-test.sh
```

has Hyprland parse `hyprland.lua` and loads the bar in a headless sway
(needs `Hyprland`, `quickshell` and `sway`). It cannot start Hyprland
itself, which needs a graphics card. To update an
installed iMac, copy `out/odimac-*.pkg.tar.zst` over and `pacman -U` it.
