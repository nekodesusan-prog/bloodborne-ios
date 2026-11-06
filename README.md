# bloodborne-ios

Bloodborne (PS4, CUSA03173 with update 1.09) on the iPhone, run from the
[bloodborne-native](https://github.com/bloodborne-native) launcher. A proof of concept: you build
it on your Mac and install it on your own iPhone with your own Apple ID. Nothing here is
distributed, and no game files are included: the app runs your own dump, and the recompiled
library is built on your Mac from your own copy.

> **A proof of concept, not the focus of development.** It was made to see how far the game runs
> on an iPhone, and what it found is written up here. The project's work goes into the macOS app,
> [bloodborne-mac](https://github.com/bloodborne-native/bloodborne-mac), and the runtime it is
> built on ([status](https://github.com/bloodborne-native/bloodborne-mac/blob/main/docs/STATUS.md)).
> iOS gains from that work, since it shares the same runtime and launcher, but it gets no
> releases and no promise of updates or support.

Built on [bbport](https://github.com/deadinside28/bloodborne_pc) by deadinside28 and
[shadPS4](https://github.com/shadps4-emu/shadPS4). The other projects whose code or designs are
used are credited in the runtime's and the app's `CREDITS.md`.

The iPhone is one example of what the project's goal makes possible: a game with no
[layer standing in for a PS4](https://github.com/bloodborne-native/bloodborne-mac/blob/main/docs/ROADMAP.md#the-ps4-layers), on any
platform. iOS has no JIT, so a game translated while it runs cannot work here: the recompiled library
is what lets it run at all.

What the iPhone allows, what it does not, and everything measured so far:
[`docs/FINDINGS.md`](docs/FINDINGS.md).

## Where it stands

- **One app:** the launcher's iOS app with the game inside. Its Play destroys the launcher's
  window, turns the phone to landscape and starts the game in the same process. The launcher's
  settings reach the game, and the game builds its executable and its patches on the phone from
  the dump (no files prepared on a Mac).
- **On an iPhone 17 Pro Max:** the title screen at 60 FPS; gameplay at 960×540 (now the screen's
  own shape, 1174×540) at 38–42 FPS uncapped in the first 20 seconds, falling as the phone heats;
  capped at 30 it holds 30 once throttled.
- **Touch:** on-screen controls (sticks, face buttons, d-pad, shoulders, Options, the touchpad,
  the settings menu), hidden while a controller is connected.
- **The limit:** an app signed with a free Apple ID has about 2 GiB of address space for
  everything but the game's own memory, and the launcher, WebKit, the recompiled library and the
  game's renderer all need part of it. When it runs out, the game stops: at start, or later when
  the system draws an animation over it. This is the open problem ([findings](docs/FINDINGS.md#the-address-space)).

## The two apps

| | The launcher's app (one app) | The game app |
|---|---|---|
| Built by | `scripts/build-launcher.sh` | `scripts/build-app.sh` |
| What it is | bloodborne-launcher's iOS app with the game linked in (`app/app_main.c` built with `BB_IOS_IN_LAUNCHER`) | The game alone, started by SDL's own `main` (`app/app_main.c`) |
| Bundle | `io.github.pablovsouza.bloodborne-ios` | `io.github.pablovsouza.bloodborne-poc` |
| Settings | The launcher's pages | `Documents/bbport.ini` and environment variables |
| Patches | Built by the game at start from the launcher's settings | `Documents/patches.bin` from the Mac |
| Used for | Playing; the direction of the work | Measurements (`scripts/trial.sh`), bisecting crashes |

## Where things are

- `app/`: the app's code. `app_main.c` sets the game up (its log, memory settings, the recompiled
  library, the screen's shape) and starts it; `orientation.m` turns the phone to landscape for
  the game and reads the screen's size; `metal_test.m` a Metal probe; the game app's Xcode
  project and `Info.plist`.
- `scripts/`: building and installing (`build-launcher.sh`, `build-app.sh`), copying the game to
  the phone (`copy-game.py`), measuring (`trial.sh`, `press.sh`, `profile.py`) and finding a
  crash (`bisect.sh`).
- `docs/FINDINGS.md`: what the iPhone allows and what was measured.
- `runtime/`: [bloodborne-runtime](https://github.com/bloodborne-native/bloodborne-runtime), the
  game (its iOS code behind `TARGET_OS_IPHONE`), with the recompiler in `runtime/recomp/` and
  [bbcpu](https://github.com/bloodborne-native/bbcpu), the CPU layer, in `runtime/bbcpu/`. The
  runtime's [`docs/IOS_POC.md`](https://github.com/bloodborne-native/bloodborne-runtime/blob/main/docs/IOS_POC.md)
  covers its iOS parts.
- `launcher/`: [bloodborne-launcher](https://github.com/bloodborne-native/bloodborne-launcher).
  The launcher's iOS project is its `src-tauri/gen/apple`.

## What you need

- A Mac with Apple Silicon, Xcode (with its command-line tools), Node.js and Rust (with the
  `aarch64-apple-ios` target: `rustup target add aarch64-apple-ios`).
- An iPhone with Developer Mode on (Settings › Privacy & Security › Developer Mode), connected by
  cable, and your Apple ID added to Xcode (Settings › Accounts). A free Apple ID works, with its
  limits: apps stop opening after seven days until installed again, at most three of them at a
  time, and no larger address space or memory limit ([findings](docs/FINDINGS.md#a-free-apple-id)).
- Your Bloodborne dump, CUSA03173 with update 1.09 merged (about 29 GB), and about as much free
  space on the phone.
- Your team ID (Xcode › Settings › Accounts, or `security find-identity -v -p codesigning`) and
  the phone's identifier (`xcrun devicectl list devices`):

```sh
export BB_IOS_TEAM=<team id> BB_IOS_DEVICE=<iPhone identifier>
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## An IPA without a Mac (this fork)

`.github/workflows/ipa.yml` builds the launcher's app with the game inside on a GitHub macOS
runner (`scripts/build-ipa.sh`): Actions › iOS app (IPA) › Run workflow, then download the
`Bloodborne-ipa` artifact. It holds no game files and no recompiled library; the runtime's
`bbcpu/` is taken from the fork's `ios-jit` branch, where the translator runs once JIT is enabled
(without JIT the game's code is interpreted, which is far too slow to play).

JIT is enabled by the app itself when you press Play, as Madeira does: its helper extension
(`app/JITHelper/`, `app/jit_builtin.m`) runs [StikJIT](https://github.com/StikDebug/StikJIT)
(MPL-2.0, built from source by `scripts/build-jit-helper.sh`) through LocalDevVPN with your
pairing file, and bbcpu's code buffer is prepared before the game starts.

1. Install `Bloodborne.ipa` with Sideloadly (or another sideloading tool) and your Apple ID, and
   keep its app extension. For the increased memory limit, add it to the app's App ID with
   GetMoreRam and install again.
2. Copy your dump into the app's `Documents/game`, and your pairing file to
   `Documents/StikJIT/pairingFile.plist` (Files, or the Apple Devices app's file sharing).
3. Turn LocalDevVPN on and press Play. The first time, the Developer Disk Image is downloaded
   (the screen stays black up to a few minutes). The game's log (`Documents/bb-ios.log`) says
   `iOS JIT: translator on` when it worked; StikDebug still works as before.

Not yet run on a device.

## Build and install

The first time (the runtime's macOS build is needed first: its dependency sources are reused):

```sh
git clone --recursive https://github.com/bloodborne-native/bloodborne-ios.git
cd bloodborne-ios
bash runtime/build.sh                       # the macOS build (runtime/deps/: about an hour)
bash runtime/scripts/ios/build-deps.sh      # runtime/deps/ios-arm64
bash runtime/scripts/ios/recomp.sh          # runtime/out/ios/librecomp.dylib, from your dump
(cd launcher && npm ci)                     # the launcher's front end
```

The launcher's app (each later build starts here):

```sh
bash scripts/build-launcher.sh              # builds the game's libraries, the launcher, signs, installs
```

`BB_LAUNCHER=<path>` builds another launcher checkout (with `npm ci` done there);
`BB_LAUNCHER_CONFIG=debug` a debug build, which leaves the game much less address space. The game
app instead: `bash scripts/build-app.sh`.

The first install, and any install after the app was removed: on the phone, Settings › General ›
VPN & Device Management, your Apple ID's developer entry, **Trust**. Installing again over the
app keeps its data.

## Put the game on the phone

The game goes into the app's `Documents/game`, the dump's folder as it is: `eboot.bin`,
`sce_sys/`, `sce_module/`, `dvdroot_ps4/` and the disc maps. Over the cable (about 33 minutes):

```sh
scripts/copy-game.py ~/path/to/CUSA03173
```

Or in Finder: select the iPhone, **Files**, Bloodborne, and drag the folder in as `game`. The
saves go to `Documents/user` (the launcher manages them; it backs them up before every start).

## Play

Open Bloodborne on the phone, set the game folder if asked, and press **Play**. The launcher's
window goes away, the phone turns to landscape behind a black screen, and the game starts. The
game closes the whole app when it ends.

Keep the phone unlocked while working with it from the Mac (Settings › Display & Brightness ›
Auto-Lock › Never): `devicectl` cannot start an app on a locked phone.

The settings that matter on the iPhone (the launcher's pages):

- **Graphics:** the aspect ratio (Auto is the screen's own shape) and the resolution, at most 540
  lines tall; effects and the frame-rate limit as on the Mac.
- **Controls:** the on-screen controls (Auto: while no controller is connected), the controller
  and its bindings. A Bluetooth controller works as on the Mac.
- **The in-game menu:** the Settings button at the top of the on-screen controls (or L3 + R3 on a
  controller).

## When something goes wrong

- **The game's log** is `Documents/bb-ios.log`, written again at every start of the app (copy it
  before opening the app again):

  ```sh
  xcrun devicectl device copy from --device $BB_IOS_DEVICE --domain-type appDataContainer \
      --domain-identifier io.github.pablovsouza.bloodborne-ios --source Documents/bb-ios.log --destination bb-ios.log
  ```

  It holds the game's output and, at the game's start and at an abort, the address space left
  (`room ...`: the largest free gap, what uses the low address space by memory tag, the memory
  left under the limit) and, every 10 seconds while playing, `Address space: ...`.
- **Live output:** start the app from the Mac with its output in the terminal (it stops when the
  app ends):

  ```sh
  xcrun devicectl device process launch --terminate-existing --console --device $BB_IOS_DEVICE io.github.pablovsouza.bloodborne-ios
  ```

- **Crash and memory reports:** `idevicecrashreport -u $BB_IOS_DEVICE -k -f Bloodborne out/reports/`
  (libimobiledevice, `brew install libimobiledevice`); a `JetsamEvent` report names the process
  the system stopped for memory. **The system log:** `idevicesyslog -u $BB_IOS_DEVICE -p Bloodborne`.
- **A system animation stops the game** (a notification, Control Center): the address space ran
  out. Known; see [findings](docs/FINDINGS.md#the-address-space).
- **The app does not open after a week:** a free Apple ID's signature expired; build and install
  again.

## Switches

Environment variables of `app/app_main.c`, set with `devicectl device process launch
--environment-variables '{"NAME":"VALUE"}'`. `devicectl` keeps them between launches: turn one off
with `0`, not by leaving it out.

| Switch | What it does |
|---|---|
| `BB_IOS_EVENT_LOG=1` | SDL logs its events into the game's log (does a touch reach the game?) |
| `BB_IOS_WEBKIT_HEAP=1` | The launcher's app: WebKit's own allocator instead of the system's (comparisons) |
| `BB_TOUCH_CONTROLS=0/1` | The on-screen controls off, or on even with a controller |
| `BB_IOS_SAVE=mac-save` | The game app: the copy of the Mac's save in `Documents/mac-save` |
| `BB_IOS_PREPARE=0` | The game app: boot the `boot-linked.bin` and `content.bin` the Mac prepared |
| `BB_IOS_CPU_ONLY`, `BB_IOS_PROBE_ONLY`, `BB_IOS_METAL_TEST`, `BB_IOS_FILE_TEST`, `BB_IOS_GUARD_TEST` | The game app's probes (`app_main.c`) |

The runtime's own switches (`BB_METAL_ARCHIVE`, `BB_FPS_LIMIT`, ...) are in its `docs/BUILDING.md`.

## Measuring with the game app

`scripts/trial.sh` runs one gameplay measurement with the game app: it writes its `bbport.ini`,
starts the game with its log, presses Cross until gameplay loads (the copied Mac save), measures
and prints the frame rate. Every run shows what it tests on screen:

```sh
BB_TEST_TITLE="What is tested" BB_TEST_DETAIL="The settings" scripts/trial.sh NAME 'INI LINES' '"ENV":"VALUE"'
```

`scripts/press.sh` holds pad buttons in the running game app; `scripts/profile.py` summarizes a
Time Profiler trace; `scripts/bisect.sh` finds the recompiled function behind a crash. The game
app reads `patches.bin` from its `Documents` (made on the Mac by `bb-patches` or `patches.py` for
its 960×540). Logs stay in the ignored `out/logs/`: they contain addresses.

## License

GPL-2.0-or-later, as the runtime.
