# Installing Wine + Delinea Connection Manager (and Fork) on Linux Mint

A walkthrough for running **Delinea Connection Manager** (Windows-only, .NET Framework 4.8)
under **Wine** on Linux Mint 22 / Ubuntu 24.04 "noble", including getting the
**external browser login** (`sslauncher://` protocol handler) to hand the auth token
back to the app.

**Bonus:** [section 10](#10-bonus-fork-git-client-under-wine) reuses the same recipe for
**Fork**, the Windows Git client, with the extra WPF-specific fixes it needs.

> **Tested on:** Linux Mint (Ubuntu 24.04 base), Wine 9.0 (Ubuntu repo), winetricks 20240105,
> Firefox Nightly and Vivaldi.
> **Status:** Delinea vault connection + external browser login working.
> Fork launches, activates, and fetches over SSH.
> **Heads-up:** Running Delinea under Wine is not supported by Delinea. For work machines,
> check with your IT/security team.

---

## Table of contents

1. [How the pieces fit together](#1-how-the-pieces-fit-together)
2. [Install Wine (with 32-bit support)](#2-install-wine-with-32-bit-support)
3. [Fix: wine32 fails because of a PPA library (libgd3)](#3-fix-wine32-fails-because-of-a-ppa-library-libgd3)
4. [Create a dedicated Wine prefix with .NET 4.8](#4-create-a-dedicated-wine-prefix-with-net-48)
5. [Install Delinea Connection Manager](#5-install-delinea-connection-manager)
6. [Find the protocol handler Delinea registered](#6-find-the-protocol-handler-delinea-registered)
7. [Bridge the protocol to Linux with a .desktop file](#7-bridge-the-protocol-to-linux-with-a-desktop-file)
8. [Log in with the external browser](#8-log-in-with-the-external-browser)
9. [Troubleshooting & harmless noise](#9-troubleshooting--harmless-noise)
10. [Bonus: Fork (Git client) under Wine](#10-bonus-fork-git-client-under-wine)
11. [Learn more](#11-learn-more)

---

## 1. How the pieces fit together

The original problem: the browser said "authenticated", then timed out, because it had
no way to hand the login back to the app.

```text
Connection Manager (Wine)  --opens-->  Browser (login page)
                                            |
                                  redirect to sslauncher://...
                                            |
                   Linux asks: "who handles x-scheme-handler/sslauncher?"
                                            |
               ~/.local/share/applications/delinea-sslauncher.desktop
                                            |
       wine ...\Delinea.ConnectionManager.Win.ProtocolHandler.exe "sslauncher://..."
                                            |
                 token handed to the running Connection Manager  ✔
```

Two separate things had to be true:

- **Windows side (inside Wine):** Delinea's protocol handler must be installed. Its
  installer is a .NET program, so the Wine prefix needs **.NET Framework 4.8**, which in
  turn needs **32-bit Wine** (`wine32`).
- **Linux side:** Wine registers `sslauncher://` only inside Wine's own registry. The
  browser runs on Linux and can't see that, so we register a matching Linux handler with
  a `.desktop` file.

---

## 2. Install Wine (with 32-bit support)

```bash
# Enable 32-bit (i386) packages alongside 64-bit (amd64) ones.
# This is called "multiarch". The .NET installers are 32-bit programs,
# so Wine needs its 32-bit half (wine32) to run them.
sudo dpkg --add-architecture i386
sudo apt update

# wine / wine64     -> the Wine runtime (64-bit)
# wine32:i386       -> the 32-bit half of Wine
# winetricks        -> helper script to install Windows components (.NET, fonts)
# cabextract        -> unpacks Microsoft .cab files (winetricks needs it for fonts)
# winbind           -> provides ntlm_auth, which Wine uses for NTLM (Windows) auth;
#                      without it you get "ntlm_auth was not found" errors
sudo apt install wine wine64 wine32:i386 winetricks cabextract winbind
```

If `wine32:i386` installs cleanly, **skip to [step 4](#4-create-a-dedicated-wine-prefix-with-net-48)**.

If you get an error like the one below, go to step 3.

```text
The following packages have unmet dependencies.
 libgphoto2-6t64:i386 : Depends: libgd3:i386 (>= 2.1.0~alpha~) but it is not going to be installed
E: Unable to correct problems, you have held broken packages.
```

---

## 3. Fix: wine32 fails because of a PPA library (libgd3)

### Why it happens

With multiarch, the 32-bit and 64-bit copies of a shared library **must be the exact same
version**. The `ondrej/php` PPA (deb.sury.org) ships a newer **64-bit-only** `libgd3`
(for PHP-GD). There's no matching i386 build anywhere, so apt refuses to install
`libgd3:i386`, and everything that depends on it (including `wine32`) fails.

The apt error names `libgphoto2`, but that's only a link in the chain:

```text
wine32:i386 -> libgphoto2-6t64:i386 -> libgd3:i386 -> version mismatch with libgd3:amd64
```

### 3a. Confirm the cause

```bash
# Shows installed/available versions for BOTH architectures,
# and which repository each one comes from.
apt-cache policy libgd3 libgd3:i386
```

What I saw (`***` marks the installed version):

```text
libgd3:
  Installed: 2.3.3-13+ubuntu24.04.1+deb.sury.org+1     <- from ondrej/php PPA
     2.3.3-9ubuntu5                                     <- Ubuntu's version
libgd3:i386:
  Candidate: 2.3.3-9ubuntu5                             <- only Ubuntu's exists for i386
```

### 3b. Simulate the downgrade first (changes nothing)

```bash
# -s = simulate. Look for "Remv" lines (packages it would REMOVE)
# or any php*-gd packages being changed. If there are none, it's safe.
apt-get install -s libgd3=2.3.3-9ubuntu5
```

My result was **1 to downgrade, 0 to remove**, with no PHP packages touched. That's the
green light.

> If the simulation wants to remove or downgrade `php*-gd` or other PHP packages,
> **stop**. Protect your PHP stack and use a Flatpak Wine manager like
> [Bottles](https://usebottles.com) instead, since it ships its own 32-bit libraries.

### 3c. Pin libgd3 to Ubuntu's version

```bash
sudo nano /etc/apt/preferences.d/libgd3-multiarch
```

```text
# Pin libgd3 to Ubuntu's build so the amd64 and i386 versions can match
# (required for wine32 via multiarch). The ondrej/php PPA ships a newer
# amd64-only build that would otherwise win.
# Pin-Priority 1001 = keep this exact version, even if it means downgrading.
Package: libgd3
Pin: version 2.3.3-9ubuntu5
Pin-Priority: 1001
```

### 3d. Downgrade + install wine32 in one go

```bash
sudo apt update
sudo apt install libgd3=2.3.3-9ubuntu5 wine32:i386
```

Check the summary line before pressing **Y**. It should look like
`0 to upgrade, N to newly install, 1 to downgrade, 0 to remove`. All the new packages
should be `:i386` (the 32-bit graphics, audio and printing stack Wine needs, about 650 MB).

### 3e. Make sure PHP is still happy

```bash
# Should print an array of GD features (FreeType, JPEG, PNG, WebP, AVIF...).
# An error here means GD broke.
php -r 'var_dump(gd_info());'

# Restart FPM so running workers pick up the library change.
# Adjust to your PHP version (check with: ls /etc/php/)
sudo systemctl restart php8.3-fpm
```

> **Future maintenance:** if sury ever releases a `php-gd` that *requires* the newer
> `libgd3`, apt will hold it back (it shows up in the "N not to upgrade" count) rather than
> break anything. At that point, choose between removing the pin (losing wine32) or moving
> Delinea to Bottles. Run `ls /etc/apt/preferences.d/` now and then to remember what's pinned.

---

## 4. Create a dedicated Wine prefix with .NET 4.8

A **prefix** is a self-contained fake Windows install (its own `C:` drive and registry).
Giving Delinea its own prefix keeps it isolated from anything else you run in Wine.

```bash
# WINEPREFIX tells wine/winetricks which prefix to use.
# NOTE: `export` only lasts for this terminal session. In a new terminal, set it again,
# or installs will land in the default ~/.wine prefix instead.
export WINEPREFIX="$HOME/.wine-delinea"

# Create / initialize the prefix (64-bit by default)
wineboot -u

# Install .NET Framework 4.8 and Microsoft core fonts.
# -q = quiet / unattended.
# This takes several minutes: it installs .NET 4.0 first, then 4.8.
# Some stages sit silently for a while, so be patient.
winetricks -q dotnet48 corefonts

# During the .NET install winetricks sets the prefix to report Windows 7.
# Bump it back up to Windows 10 afterward.
winetricks win10
```

### How to tell it worked

Near the end of the .NET section, look for:

```text
Executing touch .../dotnet48.installed.workaround
```

winetricks only writes that marker after the .NET 4.8 installer exits successfully.

Optional double-check:

```bash
# Look for a "Release" value of 528040 or higher (that means 4.8).
# reg shows it in hex, so 0x80ea8 = 528040.
wine reg query "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release
```

### Output that looks scary but is fine

- `warning: Unknown file arch of /usr/bin/wine`: on Debian/Ubuntu, `/usr/bin/wine` is a
  shell-script wrapper, so winetricks can't read its architecture. It's cosmetic.
- `warning: You are using a 64-bit WINEPREFIX...`: a generic caution, and .NET 4.8
  installed fine in 64-bit.
- Hundreds of `err:ole:CoGetContextToken`, `CoReleaseMarshalData`, `BindImageEx`, and
  `IRemUnknown_RemRelease` lines: normal noise from Microsoft's installers under Wine.

A **real** failure stops the run and ends with something like `returned status 1` or `failed`.

---

## 5. Install Delinea Connection Manager

```bash
export WINEPREFIX="$HOME/.wine-delinea"

# For an .msi installer:
wine msiexec /i /path/to/DelineaConnectionManager.msi

# Or for an .exe installer:
# wine /path/to/DelineaConnectionManagerSetup.exe
```

Then, in Connection Manager, run the **install protocol handler** option. Before .NET was
installed this failed with an "install .NET Framework" error; now it should succeed.

> Wine's `winemenubuilder` automatically creates Linux menu entries for the app's Start
> Menu shortcuts, under `~/.local/share/applications/wine/Programs/...`. Check that the
> launcher's `Exec=` line includes `WINEPREFIX=/home/<you>/.wine-delinea`, so it starts
> in the right prefix.
>
> **Watch for `wine-stable`:** these auto-made launchers sometimes call `wine-stable`,
> which is the command name from **WineHQ's** packages. Ubuntu's packages only provide
> `wine`, so the launcher silently does nothing. Check with:
>
> ```bash
> grep -rH '^Exec=' ~/.local/share/applications/wine/
> ```
>
> If you see `wine-stable`, either change it to `wine` or write your own launcher
> (see [section 10.6](#106-a-menu-launcher-that-actually-works) for an example).

---

## 6. Find the protocol handler Delinea registered

Wine's `reg.exe` **doesn't support** the `/f` search option from real Windows
(`reg query HKCR /s /f "URL Protocol"` gives "Invalid syntax"). Search the registry files
directly instead. They're plain text:

- `system.reg` holds HKEY_LOCAL_MACHINE, which includes `Software\Classes` (the main
  source of HKCR).
- `user.reg` holds HKEY_CURRENT_USER.

```bash
# awk reads each file line by line:
#   - Lines starting with "[" are registry key headers, so remember the latest one in `key`
#   - When a line contains "URL Protocol", print the key it belongs to
# Result: every key marked as a URL protocol handler, i.e. the scheme names.
awk '/^\[/{key=$0} /"URL Protocol"/{print FILENAME": "key}' \
  ~/.wine-delinea/system.reg ~/.wine-delinea/user.reg
```

What I got:

```text
system.reg: [Software\\Classes\\ftp]         <- Wine built-in
system.reg: [Software\\Classes\\http]        <- Wine built-in
system.reg: [Software\\Classes\\https]       <- Wine built-in
system.reg: [Software\\Classes\\mailto]      <- Wine built-in
system.reg: [Software\\Classes\\sslauncher]  <- Delinea (newer timestamp)
```

Now see exactly what Windows would run for it:

```bash
wine reg query 'HKCR\sslauncher\shell\open\command'
```

```text
(Default)    REG_SZ    "C:\Program Files\Delinea\Delinea Connection Manager\Delinea.ConnectionManager.Win.ProtocolHandler.exe" "%1"
```

`%1` is Windows' placeholder for the URL, the same idea as `%u` in a Linux `.desktop` file.

---

## 7. Bridge the protocol to Linux with a .desktop file

### Why use the Linux path to the exe?

In a `.desktop` file's `Exec=` line, backslashes inside quoted arguments get unescaped
**twice**, so a Windows path would need four backslashes per separator. Wine happily
accepts the **Linux** path to the same exe, so we sidestep that entirely. Your `C:` drive
is just `~/.wine-delinea/drive_c/`.

Confirm the exe is there:

```bash
ls -l "$HOME/.wine-delinea/drive_c/Program Files/Delinea/Delinea Connection Manager/Delinea.ConnectionManager.Win.ProtocolHandler.exe"
```

### Create the handler

```bash
nano ~/.local/share/applications/delinea-sslauncher.desktop
```

```ini
[Desktop Entry]
# Linux-side bridge for Delinea's Windows "sslauncher://" protocol.
# The browser asks the desktop "who handles x-scheme-handler/sslauncher?",
# finds this file, and runs Exec with the full URL substituted for %u.
Type=Application
Name=Delinea Connection Manager Protocol Handler (Wine)
Comment=Passes sslauncher:// links into Delinea Connection Manager under Wine

# Mirrors the Windows registry command:
#   "C:\...\Delinea.ConnectionManager.Win.ProtocolHandler.exe" "%1"
# but uses the Linux path to the same file (Wine accepts either).
# env WINEPREFIX=... -> must be the SAME prefix Delinea runs in, so the handler
#                       can pass the token to the already-running app.
# %u                 -> the URL from the browser (Windows' %1).
# Replace "katy" with your username (.desktop files don't expand ~ or $HOME).
Exec=env WINEPREFIX=/home/katy/.wine-delinea wine "/home/katy/.wine-delinea/drive_c/Program Files/Delinea/Delinea Connection Manager/Delinea.ConnectionManager.Win.ProtocolHandler.exe" %u

# Register for this one URL scheme
MimeType=x-scheme-handler/sslauncher;

# Plumbing, not an app to launch by hand, so hide it from the menu
NoDisplay=true
Terminal=false
```

### Register it

```bash
# Rebuild the desktop database so the new MimeType is noticed
update-desktop-database ~/.local/share/applications

# Make our file the default handler for sslauncher:// links
xdg-mime default delinea-sslauncher.desktop x-scheme-handler/sslauncher

# Sanity check; should print: delinea-sslauncher.desktop
xdg-mime query default x-scheme-handler/sslauncher
```

### Test it with a fake link

```bash
xdg-open "sslauncher://test"
```

Success looks like Wine chatter in the terminal. The handler launched, then gave up on the
bogus URL:

```text
err:combase:RoGetActivationFactory Failed to find library for L"Windows.Foundation.Diagnostics.AsyncCausalityTracer"
err:wbemprox:wql_error syntax error, unexpected TK_ID, expecting end of file
```

If nothing happens at all, run the command by hand to see Wine's output:

```bash
WINEPREFIX=~/.wine-delinea wine "$HOME/.wine-delinea/drive_c/Program Files/Delinea/Delinea Connection Manager/Delinea.ConnectionManager.Win.ProtocolHandler.exe" "sslauncher://test"
```

---

## 8. Log in with the external browser

1. Start **Connection Manager** from the menu and leave it running.
2. Restart your browser so it picks up the new handler.
3. In Connection Manager, add your **Delinea vault**, enter the URL, and choose **External browser**.
4. Log in on the page that opens.
5. When the browser asks how to open the `sslauncher` link, pick
   **Delinea Connection Manager Protocol Handler (Wine)** and tick **always**.
6. Connection Manager asks **"Are you sure you want to add this?"**. Confirm it.

✔ Done. This works with any browser (Firefox, Vivaldi, etc.), because the handler is
registered with the **desktop** via `xdg-mime`, not inside a particular browser.

---

## 9. Troubleshooting & harmless noise

| Symptom / message | What it means | Action |
|---|---|---|
| Browser says "authenticated" then times out | No Linux handler for `sslauncher://` | Do [step 7](#7-bridge-the-protocol-to-linux-with-a-desktop-file) |
| "Install protocol handler" fails asking for .NET | Prefix has no .NET Framework | Do [step 4](#4-create-a-dedicated-wine-prefix-with-net-48) |
| `it looks like wine32 is missing` | 32-bit Wine not installed | [Step 2](#2-install-wine-with-32-bit-support) / [step 3](#3-fix-wine32-fails-because-of-a-ppa-library-libgd3) |
| `reg: Invalid syntax` with `/f` | Wine's reg.exe lacks search | Use the awk command in [step 6](#6-find-the-protocol-handler-delinea-registered) |
| `ntlm_auth was not found` | winbind not installed | `sudo apt install winbind` |
| `AsyncCausalityTracer` not found | Optional Windows diagnostics component | Harmless |
| `wbemprox:wql_error` | App's WMI query isn't parseable by Wine | Usually harmless |
| `err:ole:...` floods | Wine COM noise | Harmless |
| App starts in the wrong prefix | Launcher missing `WINEPREFIX` | Add `env WINEPREFIX=...` to its `Exec=` |
| `TypeLoadException` naming a `Windows.*` type | App used a WinRT feature Wine lacks | See the WinRT rule of thumb below |
| `Couldn't get first exception ... No backtrace available` | Debugger attached too late to see the error | Capture the app's output to a log and grep for `Exception Info` |

### Check where a login redirect goes

If login still times out, open the browser dev console (**Ctrl+Shift+K** in Firefox,
**Ctrl+Shift+J** in Chromium/Vivaldi) *before* logging in, and watch the final redirect:

- `sslauncher://...` means it's the protocol handler, so check step 7.
- `http://127.0.0.1:PORT/...` or `localhost` means the app uses a loopback listener instead.
  Check whether it's listening with `ss -tlnp | grep wine`.

### Rule of thumb: switch off WinRT features in *any* Windows app

Modern Windows apps use **WinRT** (the Windows 10/11 runtime) for a handful of features,
and **Wine doesn't provide WinRT**. An app that touches one can crash outright. Fork hit
this twice (see [10.3](#103-fix-theme-crash-on-windows-10-typeloadexception) and
[10.5](#105-fix-random-crashes-from-github-notifications-sendwindowsnotification)).
For any app you run under Wine, switch off or avoid:

| Feature | Why | Do instead |
|---|---|---|
| **System / desktop / toast notifications** | Toasts are built with WinRT XML types | Turn them off, and check the setting survives a restart. If it doesn't (Fork's didn't), remove whatever triggers them, such as a connected account |
| **"Follow system theme" / auto light-dark** | Theme detection uses WinRT UI APIs | Pick a fixed theme, or a per-app Windows 7 override |
| **Windows Share, "Open with…" pickers, live tiles/badges** | Same WinRT family | Don't use them |

**How to recognize it:** a .NET app dies with `System.TypeLoadException` naming a type that
starts with `Windows.`, such as `Could not find Windows Runtime type
'Windows.Data.Xml.Dom.XmlDocument'`, often next to `RoGetActivationFactory Failed to find
library` lines. Read the stack trace above the type name (e.g.
`NotificationManager.SendWindowsNotification`, `SystemThemeHelper...`) to see which feature
triggered it, then turn that feature off.

### Known limitation: RDP sessions

Connection Manager's embedded RDP viewer relies on Windows remote-desktop components that
Wine only partly supports. If RDP sessions fail or show a blank window, that's the likely
cause. SSH sessions tend to behave better.

### Start over cleanly

The prefix is just a folder, so nothing system-wide is touched:

```bash
rm -rf "$HOME/.wine-delinea"
```

---

## 10. Bonus: Fork (Git client) under Wine

[Fork](https://git-fork.com) is a Git client with Windows and macOS builds only. It's a
**.NET Framework / WPF** app like Delinea, so it uses the same prefix recipe, plus a few
WPF-specific fixes.

> **Before you start:** steps 2 and 3 (wine32, the libgd3 pin, winbind) are
> **system-wide** and already done. Everything below is **per prefix**, because each
> prefix is its own separate fake Windows install. `.wine-fork` doesn't share
> `.wine-delinea`'s .NET.

### 10.1 Create the prefix and install Fork

```bash
export WINEPREFIX="$HOME/.wine-fork"
wineboot -u

# Same .NET + fonts recipe as Delinea (slow, noisy, normal)
winetricks -q dotnet48 corefonts

# Run Fork's installer
wine /path/to/ForkInstaller.exe
```

Fork installs per-user with **Velopack**, so it lands in the Windows profile, not
`Program Files`:

```text
~/.wine-fork/drive_c/users/<you>/AppData/Local/Fork/
├── current/            <- the live version; Velopack swaps this on update
│   ├── Fork.exe        <- what we launch
│   ├── Fork.exe.config <- telltale sign of a .NET Framework app
│   └── ...
├── packages/           <- downloaded update packages (.nupkg)
└── Update.exe          <- Velopack's updater
```

Always point launchers at **`current\Fork.exe`**. It survives self-updates, whereas
versioned folders would break.

### 10.2 Fix: WPF render crash (`0x88980406`)

**Symptom:** the icon spins, then Fork closes. Run from a terminal, you see:

```text
err:d3dcompiler:D3DCompile2 Failed to compile shader, vkd3d result -4.
COMException: Exception from HRESULT: 0x88980406
   at System.Windows.Media.Composition.DUCE.Channel.SyncFlush()
   ...
   at Fork.App.InitializeForkInstance()
```

**Why:** WPF draws windows with Direct3D. It asked Wine's built-in shader compiler (vkd3d)
to compile a shader, vkd3d failed on the syntax, and WPF's render thread died.
`0x88980406` is WPF's "render thread failed" error, and `DUCE` is WPF's composition
engine.

**Fix:** make WPF render in software, and swap in Microsoft's shader compiler as a backup.

```bash
export WINEPREFIX="$HOME/.wine-fork"

# HKCU\Software\Microsoft\Avalon.Graphics = WPF's graphics settings
# ("Avalon" was WPF's codename). DisableHWAcceleration=1 -> software rendering.
# For a Git client you won't notice any speed difference.
wine reg add 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f

# Replace Wine's vkd3d-based d3dcompiler_47 with Microsoft's native one.
# (In a crash dump, d3dcompiler_47 should then show as "PE", not "PE-Wine".)
winetricks -q d3dcompiler_47
```

### 10.3 Fix: theme crash on Windows 10 (`TypeLoadException`)

**Symptom:** after 10.2, Fork gets further and then crashes during theme setup:

```text
err:combase:RoGetActivationFactory Failed to find library for L"Windows.ApplicationModel.DesignMode"
Exception Info: System.TypeLoadException
   at Fork.UI.SystemThemeHelper.SubscribeToSystemEvents()
   at Fork.App.InitializeTheme()
```

**Why:** when Wine reports **Windows 10**, Fork follows the system light/dark theme through
**WinRT** APIs, which Wine doesn't provide. On **Windows 7** those APIs don't exist, so Fork
takes an older code path that works. (The Win7 run got *past* the theme step and crashed
later, at the render step from 10.2. That comparison is how we found it.)

**Fix:** a **per-app** Windows version override. Only `Fork.exe` sees Windows 7, and the
rest of the prefix stays on Windows 10.

```bash
export WINEPREFIX="$HOME/.wine-fork"

# Wine per-app override: HKCU\Software\Wine\AppDefaults\<exe name>
# Keyed by exe *name*, so it survives Fork updates.
wine reg add 'HKCU\Software\Wine\AppDefaults\Fork.exe' /v Version /t REG_SZ /d win7 /f
```

GUI alternative: `WINEPREFIX=~/.wine-fork winecfg`, then on the Applications tab choose
Add application, pick `Fork.exe`, and set it to Windows 7.

### 10.4 Fix: SSH fetch hangs (give Fork your Linux keys)

**Symptom:** Fetch sits on "Fetching…" (or is very slow), or authentication fails.

**Why:** Fork's bundled Git is **Git for Windows**, so its SSH looks for keys in the
*Windows* profile (`C:\users\<you>\.ssh`), which is empty in a new prefix. It can end up
stuck on an invisible prompt, such as "trust this host?".

**Fix:** make the Windows profile's `.ssh` *be* your Linux `~/.ssh`:

```bash
# Should say "No such file or directory" (if a folder exists, check it's empty, then remove it)
ls -la ~/.wine-fork/drive_c/users/<you>/.ssh

# Symlink: gives Fork your keys, ~/.ssh/config and known_hosts
ln -s ~/.ssh ~/.wine-fork/drive_c/users/<you>/.ssh

# OpenSSH refuses private keys other users can read
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* ~/.ssh/*.pem
```

**Make sure `~/.ssh/config` is Windows-friendly:**

```bash
grep -nE 'IdentityFile|IdentityAgent|ProxyCommand|Match exec|/home/' ~/.ssh/config
```

| Config line | Works in Fork? | Why |
|---|---|---|
| `IdentityFile ~/.ssh/key` | ✔ Yes | `~` resolves through the symlink |
| `IdentityFile /home/<you>/.ssh/key` | ✘ No | Git for Windows treats `/` as its own install folder |
| `IdentityAgent ~/.1password/agent.sock` | ✘ No | Windows SSH can't reach a Linux agent socket |
| `ProxyCommand nc ...` / `Match exec` | ✘ Usually not | Runs as a Windows command inside Wine |

**Debug a hang** from Fork's **Console** toolbar button, which uses its bundled Git:

```bash
GIT_SSH_COMMAND="ssh -v" git fetch -v origin
```

The last `debug1:` lines show which key it's trying or what it's waiting for.

> **Tip:** Fork's activity log (click the fetch status box) shows whether a fetch
> actually finished. First SSH connections under Wine can be slow, so a fetch that
> *looks* stuck may have quietly succeeded.

### 10.5 Fix: random crashes from GitHub notifications (`SendWindowsNotification`)

**Symptom:** Fork occasionally closes on its own mid-session, with no obvious trigger.
Wine shows a "Program Error" dialog and a debugger dump that says
`Couldn't get first exception ... No backtrace available` (not helpful on its own).

**Finding the real error:** the dump doesn't show the exception, but Fork's own output does.
Launch Fork with the *logging* launcher (see [10.6](#106-a-menu-launcher-that-actually-works)),
use it normally until it crashes, then:

```bash
grep -n -B2 -A15 'Exception Info' ~/fork-debug.log
```

What it showed:

```text
System.TypeLoadException: Could not find Windows Runtime type 'Windows.Data.Xml.Dom.XmlDocument'.
   at Fork.Accounts.NotificationManager.SendWindowsNotification(String xmlString)
   at Fork.Accounts.NotificationManager.<>c__DisplayClass29_1.<Refresh>b__3()
```

**Why:** once a **GitHub account** is connected, Fork's notification manager refreshes in the
background, and when there's something new (a PR review, mention, CI result) it shows a
**Windows 10 toast notification**. Toasts are built with WinRT (`Windows.Data.Xml.Dom`),
which Wine doesn't provide, so Fork crashes. That explains why the crashes:

- only started *after* connecting the GitHub account,
- were rare and seemed random (they only fire when there's something to notify about),
- weren't fixed by the Windows 7 override from 10.3 (this code path doesn't fall back).

**What didn't work:** unticking **Enable Notifications** in Fork's **Accounts** dialog. The
box stays unticked while Fork is open, but it's ticked again after Fork restarts, so the
setting doesn't persist (at least under Wine). The crash came back, even right at launch,
because the first refresh found unread GitHub notifications straight away.

**Fix:** **remove the GitHub account** from Fork's Accounts dialog (the `−` button). No
account means no notification refresh, so the crashing code path never runs.

What you keep and lose:

- **Still works:** fetch, pull, push, branches, history and diffs. Those use Git over **SSH**
  with your keys (see 10.4), not the Fork account.
- **Lost:** Fork's GitHub-specific integration (account notifications, PR features).

> **Worth reporting to Fork support:** the Enable Notifications checkbox doesn't persist
> across restarts, and `SendWindowsNotification` has no fallback when WinRT is missing.
> A try/catch around the toast call would fix it for any system without WinRT, not just Wine.

> **Copying the prefix to another machine?** Fork's settings live inside the prefix (the
> Windows user's `AppData`), so an `rsync`'d `.wine-fork` carries the removed account
> over too. On a *fresh* install, just don't add the GitHub account.

### 10.6 A menu launcher that actually works

Wine auto-creates `~/.local/share/applications/wine/Programs/Fork.desktop`, but it calls
`wine-stable` (see the note in [section 5](#5-install-delinea-connection-manager)) and goes
through a `.lnk` shortcut, so clicking it does nothing. Write your own launcher instead:

```bash
cat > ~/.local/share/applications/git-fork.desktop << 'EOF'
[Desktop Entry]
# App launcher for Fork (Windows Git client) running under Wine.
Type=Application
Name=Fork
GenericName=Git Client
Comment=Fork Git client (Windows version via Wine)

# Fork's own prefix + the Linux path to the exe inside its C: drive.
# "current" survives Fork's self-updates.
# Replace "katy" with your username (.desktop files don't expand ~ or $HOME).
Exec=env WINEPREFIX=/home/katy/.wine-fork wine "/home/katy/.wine-fork/drive_c/users/katy/AppData/Local/Fork/current/Fork.exe"

# Menu placement: Programming / Development
Categories=Development;RevisionControl;

# Group the running window under this launcher in the panel (check with: xprop WM_CLASS)
StartupWMClass=fork.exe

#Icon=/home/katy/.local/share/icons/fork.png
NoDisplay=false
Terminal=false
EOF

# Move Wine's broken duplicate aside (kept as a backup), then refresh the menu
mv ~/.local/share/applications/wine/Programs/Fork.desktop \
   ~/.local/share/applications/wine/Programs/Fork.desktop.bak
update-desktop-database ~/.local/share/applications

# Test it exactly the way the menu runs it (filename without .desktop), with output visible
gtk-launch git-fork
```

> **Gotcha I hit:** the `Exec=` line contains `.wine-fork` **twice**. A stray space in
> the second one (`.wine-fork /drive_c`) breaks the path, and it's easy to miss when
> you check the first one. `cat > file << 'EOF'` avoids copy-paste gremlins like
> invisible non-breaking spaces. To reveal them:
> `grep '^Exec=' file.desktop | cat -A` (`M-BM-` = non-breaking space, `^I` = tab).

**Optional: a real icon.** `Icon=` needs an **absolute path** to an image file (or the name
of an icon installed in your icon theme). You have two easy sources.

*Option A: extract it from the exe.*

```bash
sudo apt install icoutils
mkdir -p ~/.local/share/icons
# wrestool pulls the icon resources (-t 14 = icon group) out of the Windows exe
wrestool -x -t 14 "$HOME/.wine-fork/drive_c/users/<you>/AppData/Local/Fork/current/Fork.exe" > /tmp/fork.ico
# icotool splits the .ico into one PNG per size; keep the biggest
icotool -x -o ~/.local/share/icons/ /tmp/fork.ico
```

*Option B: use a downloaded logo PNG.* I keep launcher icons organized per app, e.g.
`~/webdev/icons/git-fork/logo.png`.

Then set it in the launcher:

```ini
# Absolute path; .desktop files don't expand ~ or $HOME
Icon=/home/katy/webdev/icons/git-fork/logo-3810336441.png
```

**Check the panel/taskbar icon too.** The menu uses `Icon=`, but the *running window* is
matched to its launcher via `StartupWMClass`. If the taskbar shows a generic Wine icon
instead of yours, find the real window class:

```bash
xprop WM_CLASS      # then click the Fork window
# WM_CLASS(STRING) = "fork.exe", "fork.exe"  <- use the second value
```

and set `StartupWMClass=` to it. For Fork it's `fork.exe`, which is what the launcher above uses.

**Optional: debug-logging launcher.** This is how the notification crash in 10.5 was
caught. Each launch *appends* to the log with a timestamped header, so relaunching after a
crash doesn't wipe the evidence:

```ini
# >> appends; the echo writes "=== launched <date> ===" so sessions are easy to tell apart
Exec=sh -c 'echo "=== launched $(date) ===" >> /home/katy/fork-debug.log; WINEPREFIX=/home/katy/.wine-fork wine "/home/katy/.wine-fork/drive_c/users/katy/AppData/Local/Fork/current/Fork.exe" >> /home/katy/fork-debug.log 2>&1'
```

Test it the way the menu runs it, then check the header appeared:

```bash
gtk-launch git-fork
head -5 ~/fork-debug.log      # expect: === launched Wed 30 Sep 19:20:55 EDT 2026 ===
```

Because it appends forever, check its size now and then (`ls -lh ~/fork-debug.log`), and
switch back to the plain `Exec=` line once things are stable.

### 10.7 Nice-to-haves

**A drive letter for your projects.** Wine exposes all of Linux as `Z:`, so
`/home/<you>/webdev/projects` shows up in Fork as `Z:\home\<you>\webdev\projects`. A
dedicated drive letter is tidier:

```bash
# Drive letters are just symlinks in the prefix's dosdevices folder
ln -s /home/<you>/webdev/projects ~/.wine-fork/dosdevices/p:
ls -l ~/.wine-fork/dosdevices/     # p: -> /home/<you>/webdev/projects
```

After restarting Fork, repos show as `P:\...`. It's the same files, so Fork and your Linux
terminal and editor stay in sync.

**Phantom changes: line endings and file modes.** Windows Git inside Fork and Linux Git
share the same repos, so Fork can show files as modified (yellow `M`) when nothing has
changed. Click one and check its diff:

- `changed file mode 100755 → 100644` means file permissions. This is the common one under
  Wine, because Windows Git can't read Linux's executable bit through `Z:`.
- Every line changed but identical means line endings. Git for Windows ships with
  `core.autocrlf=true` in its system config.

Confirm with `git status` in your Linux terminal: if Linux says clean, the files really
are unchanged.

*Line endings (Fork's Git only).* Fork's Git reads its global config from the **Windows**
profile, which Linux Git never reads:

```bash
cat >> ~/.wine-fork/drive_c/users/<you>/.gitconfig << 'EOF'

[core]
	# Git for Windows' system config sets autocrlf=true (convert LF <-> CRLF).
	# Our repos are LF and shared with Linux Git, so never convert.
	autocrlf = false
EOF
```

*File modes (per repo).* This **can't** go in the global file, because Linux Git writes
`filemode = true` into each repo's `.git/config`, and repo settings override global ones.
Set it per repo instead:

```bash
# One repo
git -C ~/webdev/projects/some-repo config core.fileMode false

# Every repo under projects, any depth (repos are nested by host, e.g. codeberg/pixiekat/...)
#   -name .git -type d = real repo folders; -prune = don't descend into .git itself
find ~/webdev/projects -name .git -type d -prune | while read -r gitdir; do
  repo="$(dirname "$gitdir")"
  git -C "$repo" config core.fileMode false && echo "set: $repo"
done
```

For new clones, a small zsh function does it automatically:

```zsh
# Clone like normal, then set fileMode false in the new repo.
# Usage: gclone <url> [folder]
gclone() {
  git clone "$@" || return                  # stop if the clone failed
  local dir="${2:-$(basename "$1" .git)}"   # folder: 2nd arg, or derived from the URL
  git -C "$dir" config core.fileMode false && echo "fileMode=false set in $dir"
}
```

`fileMode=false` only makes Git *stop reporting* permission differences. Executables
already committed as `100755` stay that way. To deliberately commit an executable bit:
`git update-index --chmod=+x path/to/script.sh`.

> **Dotfiles and script repos: commit from Linux, not Fork.** In repos where the
> executable bit and symlinks matter (shell scripts, `~/.local/bin`, oh-my-zsh plugins),
> staging from Fork can commit scripts as `100644`, which makes them non-executable on the
> next checkout, or turn a symlink into a plain text file. Use Fork to browse history
> and diffs there, and make commits from your Linux terminal. Plain PHP, Twig and YAML repos
> are fine to commit from Fork.

**Self-updates.** Velopack updates work under Wine. As a precaution, snapshot first:

```bash
cd ~/.wine-fork/drive_c/users/<you>/AppData/Local/Fork
cp -a current current.bak                  # before updating
# If Fork won't start afterward:
rm -rf current && mv current.bak current
```

**License activations.** A Wine prefix counts as a **new machine**, since Wine generates a
random machine ID when the prefix is created. If you hit an activation limit, email Fork
support to reset it. Once activated, **back up the prefix**, because recreating it would
likely use up another activation:

```bash
mkdir -p ~/backups
tar -czf ~/backups/wine-fork-$(date +%F).tar.gz -C ~ .wine-fork
```

### 10.8 Readability: fonts, smoothing and DPI

Out of the box, WPF apps under Wine can have jagged, cramped, or unevenly spaced text.
Three per-prefix settings fixed most of it for me, in this order of impact.

**1. Font smoothing (anti-aliasing).** Wine often defaults to *no* smoothing:

```bash
export WINEPREFIX="$HOME/.wine-fork"

# rgb = ClearType-style subpixel smoothing for the most common LCD layout.
# Colored fringes on text? Try fontsmooth=bgr, or fontsmooth=gray for plain anti-aliasing.
winetricks fontsmooth=rgb
```

**2. Replace Segoe UI with a good Linux font.** Fork, like most modern Windows apps,
asks for **Segoe UI**, which isn't in corefonts, so Wine falls back to something poor. Wine's
font *replacement* table redirects that request:

```bash
# See which candidates you have installed
fc-list : family | grep -iE 'noto sans$|^ubuntu$|inter|dejavu sans$|cantarell' | sort -u

# When an app asks for "Segoe UI", give it this font instead
wine reg add 'HKCU\Software\Wine\Fonts\Replacements' /v 'Segoe UI' /t REG_SZ /d 'Noto Sans' /f
```

Fonts hint differently at small sizes, so try a couple (`Ubuntu`, `DejaVu Sans`, `Inter`...),
restarting Fork after each change.

**3. Raise the DPI.** At the default 96 dpi, small WPF text snaps to whole pixels unevenly,
so letter spacing looks wobbly ("dup lcate"). A higher DPI gives each glyph more pixels,
which evens out the spacing and scales the whole UI, including buttons and click targets.
That's good for accessibility.

```bash
WINEPREFIX=~/.wine-fork winecfg
# Graphics tab -> Screen resolution: 120 (125%) is a good start; 144 (150%) on large/high-res screens
```

> **Trade-off:** some softness remains because of the software-rendering fix from 10.2.
> WPF's CPU text path isn't as crisp as its GPU path. We need that fix to stop the
> crash, so DPI and font choice are the knobs left to turn.
>
> **Tip:** these are all per-prefix, so apply the same three to `.wine-delinea` for
> nicer text in Connection Manager too.

### 10.9 Fork: harmless noise

| Message | Meaning |
|---|---|
| `Cygwin WARNING: Couldn't compute FAST_CWD pointer` (on every Git command) | Git for Windows' MSYS2 runtime can't find an internal pointer in Wine's reimplemented `ntdll`, so it falls back to a slower method that works. Ignore the "update Cygwin" advice. |
| `RoGetActivationFactory ... Windows.ApplicationModel.DesignMode` | WinRT lookup Wine can't satisfy; harmless once the Win7 override is set |
| `AsyncCausalityTracer`, `wbemprox:wql_error`, `err:ole:...` | Same .NET-under-Wine noise as Delinea |

### 10.10 Known limitations: WebView2 and the Console button

Fork ships **WebView2** (`Microsoft.Web.WebView2.*.dll`), Microsoft's Edge-based embedded
browser, for some panels. Wine 9.0 doesn't provide it. If a panel shows up blank or Fork
crashes when you open a particular view, run it from the terminal and look for `WebView2`
or `msedgewebview2` in the output.

**The Console toolbar button** opens Git for Windows' `bash.exe` in Wine's console window.
You get the FAST_CWD warning and a cursor, but no usable prompt, because MSYS2's bash
expects a Windows pseudo-terminal that Wine's console only partly emulates. It's a Wine
limitation. **Use your native Linux terminal instead**, in the same repo folder: you get
your real Git, shell and SSH agent, and Fork picks up the changes on its next refresh.

---

## 11. Learn more

- **[freedesktop.org Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)**:
  `Exec=` field codes (`%u`, `%f`), quoting and escaping rules, `MimeType`, `NoDisplay`.
- **[freedesktop.org shared MIME / xdg-utils](https://www.freedesktop.org/wiki/Software/xdg-utils/)**:
  how `xdg-open` and `xdg-mime` decide which app handles a file or URL.
- **`man apt_preferences`**: apt pinning, Pin-Priority values, and why 1001 forces a downgrade.
- **[Debian wiki: Multiarch/HOWTO](https://wiki.debian.org/Multiarch/HOWTO)**: why
  i386 and amd64 library versions must match.
- **`winetricks list-all`**: every component winetricks can install.
- **[WineHQ AppDB](https://appdb.winehq.org/)**: per-app compatibility notes; searching
  other .NET 4.8 apps turns up useful prefix tweaks.
- **[WineHQ Wiki: Wine User's Guide](https://gitlab.winehq.org/wine/wine/-/wikis/Wine-User%27s-Guide)**:
  prefixes, `winecfg`, registry, and DLL overrides.
- **[Bottles](https://usebottles.com)**: a Flatpak Wine manager; the fallback if the
  multiarch pin ever becomes a problem.
- **[Microsoft Learn: WPF graphics rendering registry settings](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/graphics-multimedia/graphics-rendering-registry-settings)**:
  `DisableHWAcceleration` and the other `Avalon.Graphics` switches.
- **WineHQ Wiki: "Useful Registry Keys"**: `AppDefaults` per-app overrides (Windows
  version, DLL overrides) and more.
- **`man fonts-conf` / `fc-list`**: how Linux finds and names fonts (the names Wine's
  `Fonts\Replacements` table expects).
- **[Velopack docs](https://docs.velopack.io)**: how the `current` / `packages` /
  `Update.exe` layout and self-updates work.
- **[Git for Windows FAQ](https://github.com/git-for-windows/git/wiki/FAQ)**: MSYS2 path
  handling, `core.autocrlf`, and `core.fileMode`.
