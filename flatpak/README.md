# Task Manager TMOG — Flatpak

Repackages the upstream binary release `TMOG-Task-Manager-Linux-x86_64.tar.gz`
(version 0.1.1) as a Flatpak. There is no source tree; the app is proprietary and
ships only as a prebuilt binary, so this is a repackage, not a build from source.

## Build

The upstream tarball is **not** in this repository — it is a proprietary binary
release and is not redistributable here. Fetch
`TMOG-Task-Manager-Linux-x86_64.tar.gz` (version 0.1.1) from
<https://www.tmog.org/> and drop it next to the manifest, then:

```sh
cd flatpak
sha256sum -c <<<'4d319d3d27f513e83801daeec8eb64cb78ddec1f6483bbe90d57d11e607af39d  TMOG-Task-Manager-Linux-x86_64.tar.gz'
./build.sh
flatpak run com.tmog.taskmanager
```

`build.sh` pulls `org.kde.Platform//6.10` and `org.kde.Sdk//6.10` from flathub
(the SDK is ~1–2 GB) and then runs `flatpak-builder --user --install`.

If you invoke `flatpak` by hand: the `flathub` remote exists in both system and
user scope, so always pass `--user`, otherwise the command stops and asks which
remote to use.

## Known limitation: the process list only sees the sandbox

**The process list, "end task", and priority changes do not work.** This is a
hard property of Flatpak, not a packaging bug, and no permission flag fixes it.

`flatpak run` passes `--unshare-pid` and `--proc /proc` to bwrap unconditionally,
so the app gets a private PID namespace and a fresh procfs. `/proc` is on
flatpak's no-export list, so `--filesystem=/proc` is rejected, and `/run/host`
(populated by `--filesystem=host`) contains `usr`, `etc`, `os-release`, fonts and
`monitor` — never `proc`.

Measured inside a sandbox launched with `--filesystem=host --device=all`:

| | sandbox | host |
|---|---|---|
| `ls /proc \| grep -c '^[0-9]'` | **4** | **486** |

(A snapshot — the host figure moves around, the sandbox figure does not.)

Everything else reads real, host-wide values, because the global files in procfs
are not PID-namespaced and `/sys/class` and `/sys/devices` are bind-mounted from
the host read-only. Verified:

| Source | Result |
|---|---|
| `/proc/stat`, `/proc/cpuinfo`, `/proc/meminfo`, `/proc/vmstat` | host-wide |
| `/proc/diskstats` | 26 rows — identical to host |
| `/proc/net/dev`, `/proc/net/tcp` | row-for-row identical to host |
| `/sys/class/hwmon` | present |
| `/sys/class/powercap` | `intel-rapl` present |
| `/sys/class/power_supply` | `AC0`, `BAT0` present |
| `/sys/class/block`, `/sys/dev/block` | present |
| `/sys/devices/system/cpu/*/cpufreq` | present |

Two further differences from a native run:

- `/var/run/utmp` does not exist in the sandbox. The binary carries a graceful
  message for that case ("`/var/run/utmp` does not exist or is not accessible")
  and also talks to `org.freedesktop.login1`, which does return the real
  sessions here — verified: `ListSessions` returns the live seat sessions.
- `/proc/pressure/memory` is absent — but it is absent on the host too (no PSI in
  this kernel config), so it is not a regression.

Per-socket ownership in the network panel will also be blank: the sockets in
`/proc/net/tcp` are all there, but their owning host PIDs cannot be resolved.

If you need full process management, run the binary from the tarball natively.

## Permissions

| Flag | Why |
|---|---|
| `--share=ipc`, `--socket=wayland`, `--socket=fallback-x11`, `--device=dri` | Qt 6 Widgets GUI; the binary links `libQt6OpenGL`, `libEGL` and `libGLX` |
| `--share=network` | Qt Network, and the `tmog.org` TMOG Pro licence check |
| `--socket=pulseaudio` | the binary links `libQt6Multimedia` against `libpulse`; drop it if the audio panel is unused |
| `--socket=system-bus` | services/units panel and logged-in users, via `sd_bus_open_system`. See the caveat below — the narrower `--system-talk-name` does not work here |

There is deliberately no `--filesystem=` grant: every data source the binary
touches is `/proc`, `/sys`, or the D-Bus system bus, all already reachable.

### Why `--socket=system-bus` and not `--system-talk-name=`

The obvious, narrower grant would be
`--system-talk-name=org.freedesktop.systemd1` plus
`--system-talk-name=org.freedesktop.login1`. **It does not work.** Those flags
make flatpak route the connection through `xdg-dbus-proxy` for filtering, and
libsystemd's sd-bus — which is what this binary uses — cannot speak through that
proxy.

Measured with a small probe built against `libsystemd` and run inside the real
app sandbox:

```
-- with --system-talk-name (proxied) --
  sd_bus_open_system: 0 (ok)
  ListUnits    FAILED: System.Error.ENOTCONN: Transport endpoint is not connected
  ListSessions FAILED: System.Error.ENOTCONN: Transport endpoint is not connected
  ** WARNING **: Invalid message header read      <- from /usr/bin/xdg-dbus-proxy

-- with --socket=system-bus (direct) --
  sd_bus_open_system: 0 (ok)
  ListUnits    OK: 679 units
  ListSessions OK: 2 sessions
```

The connection opens either way; it is the first method call that fails. GDBus
clients work through the same proxy without trouble, so this is specific to
sd-bus. `--socket=system-bus` bypasses the proxy and works, at the cost of
unfiltered system bus access — which is why Flathub does not accept it. That
trade-off is deliberate here.

## Notes on the packaging

- App ID `com.tmog.taskmanager` is reused from the metainfo already in the
  tarball; the shipped `.desktop` and metainfo filenames already match it.
- Icons are renamed from `tmog-task-manager.png` to `com.tmog.taskmanager.png`
  during the build, and the desktop file's `Icon=` key is rewritten, because
  Flatpak only exports icons named after the app ID.
- `com.tmog.taskmanager.metainfo.xml` in this directory overrides the one in the
  tarball. It adds the sandbox caveat to the description and a `<releases>`
  entry, which `appstreamcli validate` requires.
- The manifest uses a local `path:` source because there is no public upstream
  release URL to point `url:` at — the TMOG source and releases are not on
  GitHub. Swap in `url:` if one ever appears; the `sha256` is unchanged.
- `.gitignore` excludes the tarball along with the build output, so the
  proprietary binary never lands in this public repo.

### Behaviour notes

At startup the app extracts a bundled splash video and writes it as `logo.mov`
into its current working directory. Inside the Flatpak that lands in the
sandbox's private `/tmp`, so — unlike a native run — it leaves nothing behind on
the host.

Settings go to `$HOME/.var/app/com.tmog.taskmanager/config/` as usual.

### Runtime choice

`org.kde.Platform//6.10` ships Qt 6.10.3, glibc 2.42 and GLIBCXX 3.4.34. The
binary needs at most `Qt_6.8`, `GLIBC_2.38` and `GLIBCXX_3.4.31`, and all twelve
of its direct `DT_NEEDED` libraries — including `libQt6Multimedia.so.6`,
`libQt6Svg.so.6` and `libsystemd.so.0` — are present in that runtime.
