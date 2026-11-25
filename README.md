# OpenDisplay iMac

Turns a 2017 Retina iMac that runs [Omarchy](https://omarchy.org) into three
things, one key press apart:

| Keys | Environment | |
|---|---|---|
| **Ctrl+Alt+1** | Mac display | The screen of a MacBook over a Thunderbolt cable, using [OpenDisplay](https://github.com/peetzweg/opendisplay). Where the session starts. |
| **Ctrl+Alt+2** | Gaming | The screen of a Windows PC, streamed over the network with [Moonlight](https://moonlight-stream.org) |
| **Ctrl+Alt+3** | Desktop | Omarchy itself, untouched: its bar, menus, themes, keys and programs |

The keys are pressed on a keyboard attached to the iMac and work everywhere,
also during a game. They are the **number keys**: Ctrl+Alt+F1 to F6 are
something else (Linux's virtual terminals).

This used to be an Arch Linux image of its own, with a small desktop made to
look like Omarchy's. It is now an add-on to a real Omarchy: Omarchy is
installed on the iMac with Omarchy's installer, and this adds the Mac display
and gaming to its session as two more workspaces, plus the two drivers the
iMac18,3 needs for its 5K panel and its speakers. The last version of the
image is commit `8b9a52d` (`odimac` 0.7.2).

- Power on and log in (see "Power-on and locking"): the session starts on
  the Mac display.
- Plug a Thunderbolt cable into the MacBook: the panel lights up and the Mac
  extends onto it on its own.
- Unplug, or let the Mac sleep: the panel goes dark a minute later.
- Gaming starts the first time its keys are pressed and keeps running in the
  background afterwards. Gaming and the desktop return to the Mac display
  after ten minutes without input.
- "Mac Display" and "Gaming" are also installed as applications, for
  Omarchy's app list (Super+Alt+Space), and the three keys are in its
  keybindings menu (Super+K).

## Status

**Nothing of the Omarchy version has run on the iMac yet.** What is known:

| | |
|---|---|
| The pieces carried over unchanged (receiver, Moonlight launcher, panel policy, Thunderbolt wake sources) | confirmed on the iMac18,3 under the Arch image, `odimac` 0.7.2 |
| Switching logic in Omarchy's session, including Omarchy's configuration reloads | tested here against a stand-in for Hyprland's Lua API (`tests/session-test.sh`) |
| Panel policy beside Omarchy's own idle handling | tested here with Hyprland stubbed (`tests/powerd-test.sh`) |
| `odimac-setup` | tested here with the system commands stubbed (`tests/setup-test.sh`) |
| 5K driver on Omarchy's kernel (linux-omarchy 7.2.15-5) | the patches apply without fuzz and the driver compiles, with a general kernel configuration, not Omarchy's; one patch had to be re-diffed, see "The 5K driver". **Not loaded on an iMac.** |
| Sound driver on Omarchy's kernel (linux-omarchy 7.2.15-5) | its patches apply and it compiles. **Not loaded on an iMac.** |
| Building the packages (`./build.sh`, `./install.sh`) | **not run**: Omarchy's package servers were out of reach where this was written |
| Everything on the iMac under Omarchy: the session integration, NetworkManager on the cable, Omarchy's firewall, the pointer shield, the drivers | **not tested** |

Expect to fix things on the first try; `odimac-doctor` is there to say
which. Under the Arch image these were confirmed, and are the mark to reach
again: the panel at 5120x2880, the Mac connecting by itself on plug-in, H.264
at 4096x2304 at about 45 frames per second and HEVC at native 5120x2880,
gaming with Apollo on the PC, brightness, sound from the speakers, and going
between a running game and the desktop without the freeze the driver fix
cured.

## Install

1. **Install Omarchy on the iMac**, version 4 or later, with its own
   installer from [omarchy.org](https://omarchy.org). That erases the disk,
   macOS included. An iMac with a Fusion Drive shows two disks; install onto
   the SSD. Update it once (Omarchy menu → Update) and restart, so that the
   running kernel is the current one.
2. **In a terminal on the iMac** (Super+Return), get this repository and run
   the installer:

   ```bash
   git clone https://github.com/sneakersgames/living-screen
   ```

   ```bash
   cd living-screen && ./install.sh
   ```

   It builds the packages for this machine as it is now, installs them, and
   runs `odimac-setup`. It asks for your password where it needs it. The
   first run takes a while: the receiver is compiled, and for the 5K driver
   the kernel's source is fetched (about 8 GB of disk in `out/`) and the
   graphics driver built, 20 to 40 minutes on this iMac.
3. **Restart.** The drivers are used from then on, and the session starts on
   the Mac display.

Options: `--autologin` (see "Power-on and locking"), `--no-drivers` (on
another model, or to try the rest first), `--packages DIR` (install packages
built elsewhere, see "Build elsewhere").

### What it changes on the Omarchy system

| | |
|---|---|
| Packages | `opendisplay-receiver`, `odimac`, `odimac-amdgpu5k`, `odimac-cs8409`, and from Arch's repositories `moonlight-qt`, `swayidle` and what else of those four's dependencies Omarchy did not have |
| `~/.config/hypr/hyprland.lua` | one line at the end that loads `/usr/share/odimac/hyprland.lua` |
| Omarchy's firewall (ufw) | lets everything in on the Thunderbolt cable (`thunderbolt0`, `thunderbolt1`) |
| `odimac-firewall.service` | keeps the receiver invisible on every other network; it also stops this machine finding things by name on the local network, see "Known limits" |
| NetworkManager | a profile for the Thunderbolt cable: link-local addresses only |
| Kernel settings | larger network buffers for Moonlight (`/usr/lib/sysctl.d/50-odimac.conf`), `thunderbolt-net` loaded at start |
| Initramfs | rebuilt with the 5K driver in it |
| A graphics card reset | restarts the login manager, so the session comes back instead of staying black |

Nothing of Omarchy's own files is edited, and Omarchy's updates do not touch
any of this. To take it out again:

```bash
odimac-setup remove
```

```bash
sudo pacman -Rns odimac odimac-amdgpu5k odimac-cs8409 opendisplay-receiver
```

### After an Omarchy update

Omarchy's updates go through as usual. **When one brings a new kernel, the
two drivers are not in it**: they are built for one exact kernel. The new
kernel then starts with its own graphics driver, at 3840x2160 instead of
5120x2880, and without sound from the speakers. Nothing else breaks.

So, after an update and **before restarting**, in the repository:

```bash
git pull && ./install.sh
```

It builds the drivers for the new kernel (it picks the installed one, not the
running one). Restarted too early? Run it anyway, and restart once more.
`odimac-doctor` says when the drivers are for another kernel than the one
running. If the 5K patches do not apply to a new kernel, the build stops and
says so, nothing is installed, and the iMac stays at 3840x2160 until the
patches are ported; the build never produces a driver from patches that do
not match exactly.

### Build elsewhere

With Docker, on Linux or a Mac:

```bash
./build.sh
```

This produces `out/*.pkg.tar.zst`, built in a container that is made an
Omarchy as far as packages go: Omarchy's repository, its snapshot of Arch,
its kernel. The drivers fit an iMac whose Omarchy is on the same channel
(`OMARCHY_CHANNEL=stable`, `rc` or `edge`) and updated to the same kernel.
Copy `out/*.pkg.tar.zst` to the iMac and, in this repository there:

```bash
./install.sh --packages /path/to/the/packages
```

- **Apple silicon Mac:** the build runs in an emulated x86_64 container. In
  Docker Desktop turn on Settings → General → "Use Rosetta for x86_64/amd64
  emulation".
- **First build is slow, later ones are not.** The receiver and the two
  drivers are kept in `out/cache` and rebuilt only when what they are made
  from changes. Delete `out/cache` to start over.
- **Other receiver source:** it is built from upstream tag `v1.30.3` plus
  the patches in `patches/opendisplay`; set `OPENDISPLAY_REPO` and
  `OPENDISPLAY_REF` for a fork or another tag, and `OPENDISPLAY_PATCHES=0`
  to leave the patches out.
- **Without Docker:** the "Build packages" workflow under the repository's
  Actions tab builds the same packages and attaches them to the run.

## Power-on and locking

Under the Arch image the iMac was an appliance with no login. Omarchy has
one, and two things follow:

- **At power-on.** An Omarchy installed with disk encryption asks for the
  disk's passphrase and then logs in by itself. One installed without asks
  for your password at each start; `odimac-setup --autologin` (or
  `./install.sh --autologin`) makes it log in by itself, which means anyone
  who can switch the iMac on is in.
- **When idle.** On the desktop, Omarchy starts its screensaver after two and
  a half minutes without input and locks after five. On the Mac display and
  during a game it does neither: nobody touches the iMac's keyboard then,
  and the picture must stay. But if the desktop was left showing and locked
  itself, the session returns to the Mac display behind the lock screen, and
  a Mac plugged in later lights the panel on the lock screen: type your
  password on the iMac, once. To have Omarchy never lock on idle, press
  **Super+Ctrl+I** (its "Stay Awake" toggle).

Suspend does not work on this iMac (see "Known limits"); leave it out of
Omarchy's power menu.

## Using it

1. On the MacBook, start OpenDisplay and plug in a Thunderbolt 3 cable (a
   real Thunderbolt cable, not a USB-C charging cable). The Mac should
   connect within about twenty seconds.
2. If it does not, press Ctrl+Alt+3, open a terminal (Super+Return) and run:

   ```bash
   sudo odimac-doctor
   ```

   It names the failing layer: not set up, a service not running, no
   5120x2880 mode, the drivers built for another kernel, no Thunderbolt
   controller, no cable link, the firewall, or the receiver not listening.

A program started while the Mac display or a game is showing, from Omarchy's
menu or one of its keys, opens on the desktop, and the desktop comes to
the front with it. Omarchy's workspace keys (Super+1 and so on) lead to the
desktop from anywhere. Brightness and volume keys are Omarchy's.

The Mac's picture has the size Omarchy gives the panel: at scale 2, set in
Omarchy's monitor panel, the Mac builds a "looks like 2560x1440" display on
the 5K panel.

## Gaming

The iMac can also be the only screen of a Windows PC, for games: the PC
streams its picture over the network and the iMac shows it with Moonlight.
Keyboard, mouse and controllers plugged into the iMac are passed on to the
PC.

Ctrl+Alt+2 starts Moonlight on first use. It returns to the Mac display when
Moonlight quits, or after ten minutes without input (`MODE_IDLE_RETURN`; a
running stream does not count as idle). The Mac's session carries on in the
background while another environment is showing.

Set-up, once:

1. On the PC, install [Apollo](https://github.com/ClassicOldSong/Apollo)
   (Sunshine with a built-in virtual display, so the PC needs no monitor of
   its own afterwards) or [Sunshine](https://github.com/LizardByte/Sunshine)
   with an HDMI dummy plug. This step needs a screen on the PC.
2. Put the iMac on the same network as the PC, by cable for preference.
3. Press Ctrl+Alt+2. In Moonlight choose "Add PC manually" and enter the
   PC's address: Moonlight cannot find the PC by itself, because
   `odimac-firewall` blocks the discovery protocol that would also show the
   receiver to Macs on the network. Moonlight shows a PIN; enter it in
   Apollo's web page (`https://<PC address>:47990`, from any browser).
4. Optional: set `GAME_HOST` in `/etc/odimac/odimac.conf` to the PC's
   address. Ctrl+Alt+2 then goes straight into the stream.

Moonlight starts out at 2560x1440 and 60 frames per second, which is exactly
half the panel in each direction. During a stream, Ctrl+Alt+Shift+S shows
Moonlight's statistics and Ctrl+Alt+Shift+Q ends the stream.

## What is in it

| Piece | What it does |
|---|---|
| `opendisplay-receiver` | Upstream's Linux receiver, built from a release tag plus `patches/opendisplay` |
| `hyprland.lua` | What is added to Omarchy's Hyprland session: the receiver full screen on workspace `display`, Moonlight on `game`, the three keys, and the switching between the environments |
| `odimac.target` | The services of the session (systemd user units): `odimac-receiver`, `odimac-powerd`, `odimac-idle`, `odimac-shield` |
| `odimac-powerd` | On the Mac display, lights the panel while a sender is connected or a cable was just plugged in and darkens it otherwise; lights it on the way to gaming and the desktop, and leaves it to Omarchy there |
| `mode`, `game` | `/usr/lib/odimac/mode display\|game\|desktop` switches from a script or terminal; `game` runs Moonlight |
| `odimac-shield` | An invisible layer over the Mac display that takes the iMac's own pointer, see "Known limits" |
| `odimac-setup` | Turns all of this on for your user, and off again |
| `odimac-doctor` | Reports on the session, panel, decoding, sound, Thunderbolt and the receiver; runs the suspend test and a decode benchmark |
| `odimac-amdgpu5k` | The graphics driver with native 5120x2880, for one exact kernel |
| `odimac-cs8409` | Sound driver for the iMac's audio chip, which the kernel's own driver cannot play through, for one exact kernel |

Everything except the receiver and the two drivers is in the `odimac` package
(`packages/odimac/`).

## Settings

`/etc/odimac/odimac.conf`, then `systemctl --user restart odimac.target`
(that restarts the Mac display; the desktop and a running game are left
alone):

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
| `MODE_IDLE_RETURN` | `600` | Seconds without input before gaming and the desktop return to the Mac display; `0` never |
| `PANEL_POWER_CYCLE` | `auto` | See "The 5K driver" |

The desktop's own settings (scale, keys, look) are Omarchy's, in its menus
and in `~/.config/hypr`.

Logs: `journalctl -b -t odimac-receiver -t odimac-powerd -t odimac-mode`.
During a session the journal gets one `load:` line a minute (CPU use, the
receiver's share, temperatures, fan speed); `odimac-doctor load` shows the
same live.

## Known limits

- **Native 5120x2880 uses a patched graphics driver.** Apple drives the 5K
  panel as two 2560x2880 halves and the stock `amdgpu` driver only wakes
  one, giving 3840x2160. `odimac-amdgpu5k` is `amdgpu` rebuilt with the
  patch stack from
  [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3)
  (upstream thread drm/amd#4455), which presents both halves as one display,
  plus our own fix. See "The 5K driver" below.
- **Do not also apply that project's `5k` and `audio` patches.** Its patcher
  and these two packages put a driver in the same place. Its other modules
  (colour, brightness range, the Intel GPU) are separate from anything here
  and have not been tried together with it.
- **Suspend is not usable.** On the iMac18,3 the machine resumes but the
  Thunderbolt and USB controllers do not come back
  (`thunderbolt 0000:07:00.0: not ready after resume; giving up`). Keep
  `SUSPEND_AFTER=0`, and do not suspend from Omarchy's menu.
- **Nothing on the iMac finds things by name on the local network** while
  `odimac-firewall` is on: printers that announce themselves, `.local`
  names, Moonlight finding the PC. It blocks mDNS everywhere but on the
  Thunderbolt cable, because that is also how the receiver announces itself,
  and a Mac that sees the receiver on Wi-Fi tries to use it there. Omarchy's
  own firewall already refuses the connection itself, so turning this off
  costs no safety, only that Macs on the network see an iMac they cannot
  use: `sudo systemctl disable --now odimac-firewall`.
- **The stream is not encrypted.** The cable is private, and the firewalls
  keep the receiver off every other network.
- **Frame rate is set by the MacBook's encoder**, not the iMac (its log
  counts the frames it skips as `enc↓`). Measured on an iMac18,3 over the
  cable with an Apple silicon MacBook at "Best": about 45 frames per second
  with H.264 at 4096x2304, 13 to 18 ms from capture to display. OpenDisplay's
  own figure for HEVC at 5120x2880 is about 30.
- **Connecting takes about 20 seconds after the cable is plugged in.** The
  Mac finds the iMac at once but its first few connection attempts time out.
- **No audio and no keyboard or mouse forwarding** from the iMac to the Mac.
  The receiver would pass the iMac's pointer on to the Mac as touches, and
  under Hyprland that made the Mac's pointer jump back to wherever the
  iMac's pointer was resting. On the Mac display `odimac-shield` therefore
  lays an invisible layer over the receiver that takes the iMac's pointer; a
  mouse on the iMac does nothing there.
- **The freezes (still picture, dead keyboard, then the whole machine)**
  under the Arch image were traced to one bug in the 5K driver patches:
  `kernel BUG at amdgpu_dm.c`, in `dm_update_crtc_state`. It was hit by any
  request for a modeset of the already running panel that changes nothing
  the panel is sent: Hyprland changing the HDR metadata just after Moonlight
  started, the text console taking the screen at shutdown, a second
  compositor taking over.

  Two changes answer it, and both are carried over.
  `patches/amdgpu/0001-tiled-stitch-logical-modeset.patch` fixes the driver:
  such a request is recognised before anything is taken down. And
  `hyprland.lua` stops Hyprland from changing HDR, content type or direct
  scanout when a window goes full screen or leaves it; that setting applies
  to Omarchy's whole session. Omarchy does more with the screen than the
  image did (a login manager, a boot splash, a lock screen), so this is the
  first thing to look at if the iMac freezes: `odimac-doctor` says under
  "Trouble" whether the installed driver has the fix and lists the crash if
  it was logged; after a stop and a restart, `odimac-doctor last-start`
  shows the last lines logged before it.
- **Sound needs its own driver.** The 2017 iMac's audio chip (Cirrus
  CS8409 with a CS42L83) gets no sound out of the kernel's own driver.
  `odimac-cs8409` is the driver from
  [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio),
  built for the installed kernel. `odimac-doctor` has a "Sound" section.
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

- **It is built from the kernel's own source.** Omarchy's kernel
  (`linux-omarchy`) is not plain kernel.org: it carries some two hundred
  patches, a number of them in the graphics driver. A driver built from
  other source loads and then misbehaves. `scripts/kernel-source.sh`
  therefore runs the kernel package's own recipe, of the exact release that
  is installed, up to the point where the source is patched, and the build
  stops if the resulting headers differ from the installed kernel's.
- **One of the community patches is carried here in a re-diffed form**
  (`patches/amdgpu/linux-omarchy/`). On linux-omarchy 7.2.15-5 one of
  Omarchy's patches adds lines next to two places where the stitch patch
  also adds its own, so the original no longer matches line for line. The
  re-diffed patch adds the same lines in the same places; the build uses it
  only where the original does not apply.
- **Black or garbled screen with the 5K driver:** at the boot menu choose
  Omarchy's entry, press `e` and add `module_blacklist=amdgpu` to the kernel
  line. The system then starts on the firmware's plain framebuffer, without
  the graphical session. Log in on the console and remove the driver:

  ```bash
  sudo pacman -R odimac-amdgpu5k
  ```

  The stock driver (3840x2160) is used from the next start. Omarchy's boot
  menu also has Snapshots, which start the system as it was before an
  update.
- **Half the picture stretched across the panel:** `odimac-powerd`
  power-cycles the panel once when the session starts to correct this
  (`PANEL_POWER_CYCLE`); if it still happens, log out and in.
- **Kernels 7.1 and 7.2 only.** The patches support these series; for
  another the build stops.

## Develop

No hardware, no Omarchy and no root needed:

```bash
tests/powerd-test.sh
```

runs the panel and suspend policy against a fake sysfs, with Hyprland
stubbed (needs `jq`).

```bash
tests/session-test.sh
```

loads `hyprland.lua` against a stand-in for Hyprland's Lua API and replays
key presses, window and idle events and a reload of the configuration
through it (needs `lua`), and runs the `mode` and `game` scripts with
`hyprctl` and Moonlight stubbed.

```bash
tests/setup-test.sh
```

runs `odimac-setup` against a scratch home directory, with `sudo` and the
system commands stubbed.

```bash
tests/desktop-test.sh
```

has Hyprland parse `hyprland.lua` by itself, which also checks the arguments
of the dispatchers in it, and loads the pointer shield in a headless sway
(needs `Hyprland`, `quickshell` and `sway`). None of these can start
Omarchy's session, which needs a graphics card: what this does on the iMac
is only known from the iMac.

### Trying a change on the iMac

Over ssh, which is also the way to read its logs (`sudo systemctl enable
--now sshd` on the iMac, once; Omarchy's firewall needs `sudo ufw allow
ssh`). For a change to the `odimac` package alone, build without the
drivers and install it:

```bash
KREL=none scripts/build-packages.sh out && sudo pacman -U out/odimac-[0-9]*.pkg.tar.zst
```

Then log out and in. A change to `hyprland.lua` alone is picked up by
`hyprctl reload`, and one to a script by `systemctl --user restart
odimac.target`.
