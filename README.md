<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/English-1e1e2e?style=for-the-badge&labelColor=cba6f7" alt="English"></a>
  <a href="README.pt-BR.md"><img src="https://img.shields.io/badge/Portugu%C3%AAs-1e1e2e?style=for-the-badge&labelColor=a6e3a1" alt="Português"></a>
  <a href="README.es.md"><img src="https://img.shields.io/badge/Espa%C3%B1ol-1e1e2e?style=for-the-badge&labelColor=fab387" alt="Español"></a>
  <a href="README.ru.md"><img src="https://img.shields.io/badge/%D0%A0%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9-1e1e2e?style=for-the-badge&labelColor=89b4fa" alt="Русский"></a>
</p>

<p align="center"><img src="assets/logo-256.png" width="128" alt="Linuxify logo"></p>
<h1 align="center">Linuxify</h1>
<p align="center"><b>Make Windows 11 look and feel like a tiling Linux desktop — and switch it all on or off with one click.</b></p>

<p align="center">
  <img src="docs/panel-general.png" width="49%" alt="Panel - General">
  <img src="docs/panel-terminal.png" width="49%" alt="Panel - Terminal">
</p>
<p align="center"><img src="docs/desktop-widget.png" width="70%" alt="Desktop widget"></p>

## What is it?

Linuxify is a small tray app plus a modern settings panel that glues together a set of great open-source tools:

- [GlazeWM](https://github.com/glzr-io/glazewm) — tiling window manager
- [Zebar](https://github.com/glzr-io/zebar) — top status bar
- [Windhawk](https://windhawk.net) — taskbar mods
- a Catppuccin Mocha theme for Windows Terminal, [Starship](https://starship.rs) prompt and [fastfetch](https://github.com/fastfetch-cli/fastfetch) banner

Everything Linuxify changes is backed up first, and *Linux mode* can be turned off at any time to get your normal Windows back.

## Features

- **One-click Linux mode** — left-click the tray icon (or press **Ctrl+Alt+L**) to start/stop GlazeWM + Zebar and apply/remove the terminal theme.
- **Modern panel** — Windows 11 style window with acrylic glass, dark title bar, sidebar navigation, rounded cards, custom toggles and status pills. Glass can be turned off or tuned (*General > Panel glass*).
- **Per-tool control** — turn GlazeWM, Zebar, Windhawk and the terminal theme on/off individually, and install or uninstall them with winget straight from the panel.
- **Terminal tab** — paste any ASCII art banner, pick color scheme, ASCII color, font, size, opacity and acrylic, with live preview. *Restore original* brings back your previous `settings.json` and the default logo.
- **GlazeWM exceptions** — choose apps that should never be tiled (games, launchers, tools). Add by process name or from a list of open windows.
- **Window transparency** — make any window translucent with a live slider and save it as a per-app rule that is re-applied automatically.
- **Desktop terminal widget** — an optional fastfetch card pinned to the desktop, with corner choice, size (60–120%) and a close button.
- **4 languages** — English, Português (BR), Español and Русский for the panel, tray menu, installer and uninstaller. Default follows your Windows display language.
- **Safe** — every file is backed up before it is touched; the uninstaller restores the originals.

## Requirements

- Windows 11 (Windows 10 1803+ works, with a simpler blur effect)
- Windows PowerShell 5.1 (built in)
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (App Installer) to install the dependencies automatically
- Recommended: [JetBrainsMono Nerd Font](https://www.nerdfonts.com/) (the installer can install it for you)

## Install

1. Download `Linuxify-vX.Y.Z.zip` from [Releases](../../releases) and extract it anywhere.
2. Double-click **`Install.cmd`**.
3. Answer **y** to install/update the dependencies with winget (GlazeWM, Zebar, Windhawk, fastfetch, Starship and the optional Nerd Font).

The installer copies Linuxify to `%LOCALAPPDATA%\Linuxify`, backs up your existing configs, writes the Linuxify configs, adds the tray to startup (`HKCU\...\Run`, with `-Boot` so it waits for the taskbar) and starts it.

Command-line options: `install.ps1 -Yes` (no questions), `-NoDeps` (skip winget), `-NoStart` (don't start the tray).

The zip includes `Linuxify.exe` (the tray compiled with ps2exe). Without it, the tray runs from `Linuxify.ps1`.

## Usage

| Action | How |
|---|---|
| Toggle Linux mode | Left-click the tray icon or press **Ctrl+Alt+L** |
| Open the panel | Right-click the tray icon > *Open panel...* |
| Change language | Panel > *General* > *Language* |
| Glass effect | Panel > *General* > *Panel glass* (toggle + intensity) |
| Desktop widget | Panel > *General* > *Terminal on the desktop* |
| Uninstall | `Uninstall.cmd` or tray > *Uninstall everything...* |

### Panel tabs

- **General** — Linux mode, the tool cards (status, on/off, install/uninstall), start with Windows, language, desktop widget and glass settings.
- **Terminal** — ASCII banner (saved to `~/.config/fastfetch/logo.txt`), color scheme, ASCII color, font, opacity and acrylic.
- **Exceptions** — apps GlazeWM ignores. Games found by the scan are kept in the `# Jogos (Linuxify)` rule of `~/.glzr/glazewm/config.yaml`.
- **Transparency** — live opacity for any window, saved rules per app, and "apply automatically".

## Configuration files

| File | Purpose |
|---|---|
| `%LOCALAPPDATA%\Linuxify\panel.json` | Panel preferences (language, glass, ASCII color, banner) |
| `%LOCALAPPDATA%\Linuxify\desktop.json` | Desktop widget (enabled, corner, size) |
| `%LOCALAPPDATA%\Linuxify\transparency.json` | Per-app transparency rules |
| `%LOCALAPPDATA%\Linuxify\backup\` | Backups of every file Linuxify changed |
| `~/.glzr/glazewm/config.yaml` | GlazeWM config (tiling, rules, exceptions) |
| `~/.config/fastfetch/logo.txt` | Current ASCII banner (`logo-default.txt` is the default) |

Translations live in `lang/*.json` (UTF-8). New languages are welcome — copy `lang/en.json`, translate the values and open a PR.

## Uninstall

Double-click **`Uninstall.cmd`** (or tray > *Uninstall everything...*). It turns Linux mode off, removes the startup entries and restores the backed-up configs. `uninstall.ps1 -RemoveApps` also uninstalls the winget packages. Backups stay in `%LOCALAPPDATA%\Linuxify\backup` until you delete them.

## Troubleshooting

- **Ctrl+Alt+L does nothing** — another app is using the shortcut; use the tray icon instead.
- **No tray icon after sign-in** — startup waits up to about a minute for Explorer and the notification area, then retries the icon. Details are in `%LOCALAPPDATA%\Linuxify\startup.log`. If an older install is still using the previous startup command, turn *Start with Windows* off and on once (the next launch also rewrites it). Restarting Explorer brings the icon back.
- **A game or app gets tiled** — add it in *Exceptions*, or add the process name to the games rule.
- **Icons look like squares in the terminal** — install a Nerd Font and select it in the *Terminal* tab.
- **No glass effect** — requires Windows 11 (or Windows 10 1803+ for blur) and transparency effects enabled in Windows settings; you can also turn it off in *General*.

## Changelog

### v0.2.3
- At sign-in the tray waits until Explorer and the notification area are ready (`-Boot` on the startup command) before showing the icon. If creating the icon fails, it tries again and writes the error, with a timestamp, to `%LOCALAPPDATA%\Linuxify\startup.log`.
- If Explorer restarts, the tray icon is shown again.
- *Start with Windows* (installer, panel and tray menu) writes the new startup command. An existing install is updated the next time the tray starts.

## Credits

[GlazeWM](https://github.com/glzr-io/glazewm) and [Zebar](https://github.com/glzr-io/zebar) by glzr.io, [Windhawk](https://windhawk.net) by Ramen Software, [Starship](https://starship.rs), [fastfetch](https://github.com/fastfetch-cli/fastfetch), [Catppuccin](https://catppuccin.com).

## License

MIT — see [LICENSE](LICENSE).
