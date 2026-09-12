# bluefin-hyprland

[Bluefin](https://projectbluefin.io) with [Hyprland](https://hypr.land) baked into the image.

A [bootc](https://bootc-dev.github.io/bootc/) image built on `ghcr.io/ublue-os/bluefin-nvidia-open:stable`. GNOME stays exactly as Bluefin ships it; Hyprland is added alongside as a second session you pick at the login screen. Rebuilt daily so it tracks Bluefin's stable channel.

```
sudo bootc switch ghcr.io/holsee/bluefin-hyprland:stable
```

## Why an image rather than layering

`rpm-ostree install hyprland ...` works, but every layered package is re-resolved on every OS update, the set of what you added lives only in local state, and reproducing it on a second machine means replaying history. Baking the packages into an image makes the desktop a declared, versioned, signed artifact — the same reason Bluefin itself is an image and not a kickstart.

## What's in it

Everything a working Hyprland session needs that Bluefin doesn't already carry:

| Role | Package | Source |
|---|---|---|
| Compositor | `hyprland` 0.56, `hyprland-uwsm`, `uwsm` | sdegler COPR |
| Session plumbing | `xdg-desktop-portal-hyprland`, `hyprpolkitagent` | sdegler COPR |
| Lock / idle / wallpaper | `hyprlock`, `hypridle`, `hyprpaper` | sdegler COPR |
| Screenshots, colour, night light | `hyprshot`, `hyprpicker`, `hyprsunset`, `satty` | sdegler COPR / Fedora |
| Bar, clipboard, GTK theming | `waybar`, `cliphist`, `nwg-look` | sdegler COPR |
| Terminal | `ghostty` | scottames COPR |
| Launcher, notifications, power menu | `fuzzel`, `mako`, `wlogout` | Fedora |
| Hardware / audio | `brightnessctl`, `playerctl`, `pavucontrol`, `blueman`, `grim`, `slurp` | Fedora |
| Look | `papirus-icon-theme`, `qt6ct` | Fedora |
| Passwords, SSH agent | `1password`, `1password-cli` | 1Password repo |

Both COPRs are enabled only for the duration of the build and left **disabled** in the image, so they don't influence anything you layer later.

**1Password** is the RPM rather than the Flatpak because only the RPM has the SSH agent, browser integration and CLI integration. Three things make it work on bootc, all in this repo:

- It installs under `/opt`, which is `/var/opt` and not part of the image, so `build.sh` moves it to `/usr/lib/1Password` and `tmpfiles.d` links `/opt/1Password` back at boot.
- Its setgid helpers belong to the `onepassword`, `onepassword-cli` and `onepassword-mcp` groups. Groups added to the image's `/etc/group` never reach an existing system, so they are declared with fixed GIDs in `sysusers.d` and created at boot.
- Its polkit policy normally lists the machine's users at install time; the build has none, so `build.sh` fills in `unix-user:holsee`. Change it if you fork this.

**Not in it, deliberately:**

- **kitty.** The `hyprland` package recommends it. Weak dependencies are disabled for every install in `build.sh`, so it stays out.
- **Any configuration.** No keybindings, no theme, no `~/.config`. The image is packages and session entries; your dotfiles are yours. Nothing in `/usr/lib/systemd/user-preset` either — enabling `waybar.service` image-wide would break the GNOME session that this image keeps as a fallback.
- **Development tooling.** That belongs in Homebrew or a devcontainer, not the OS image.

## Switching to it

From any Fedora Atomic / Universal Blue system:

```bash
sudo bootc switch ghcr.io/holsee/bluefin-hyprland:stable
systemctl reboot
```

Or with rpm-ostree, verifying the signature:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/holsee/bluefin-hyprland:stable
```

At GDM, click your user, then the gear icon that appears — pick **Hyprland (uwsm-managed)**. The plain **Hyprland** entry also works; the uwsm one activates `graphical-session.target` so user services (waybar, mako, portals, gvfs) start the systemd way.

If you were previously layering these same packages, drop the layer afterwards or rpm-ostree will report them as inactive requests:

```bash
rpm-ostree uninstall hyprland hyprland-uwsm uwsm xdg-desktop-portal-hyprland hyprpolkitagent \
  hyprlock hypridle hyprpaper hyprshot hyprpicker hyprsunset waybar cliphist satty nwg-look \
  fuzzel mako wlogout grim slurp brightnessctl playerctl pavucontrol blueman papirus-icon-theme qt6ct
```

## Things that have moved past their documentation

Hyprland 0.56 and hyprpaper 0.8.4 changed several things that most guides — and most LLM answers — still get wrong. Nearly all of these fail **silently**: the command returns `ok` and nothing happens.

- **The `.conf` format is deprecated.** 0.56 logs `You are using the .conf config format, support for which will be removed in Hyprland 0.57`. The primary config is now Lua (`~/.config/hypr/hyprland.lua`); a reference ships at `/usr/share/hypr/hyprland.lua` with type stubs in `/usr/share/hypr/stubs/`.
- **Window rules are blocks, not one-liners.** `windowrule = float, class:^(foo)$` is rejected. In `.conf` it's a named block with a nested `match { }`; in Lua it's `hl.window_rule({ name = ..., match = { class = ... }, float = true })`.
- **`hyprctl keyword` doesn't work under a Lua config** (`keyword can't work with non-legacy parsers`). Use `hyprctl eval 'hl.config({ general = { gaps_in = 0 } })'`.
- **Legacy `hyprctl dispatch` verbs are rejected too.** `dispatch focuswindow address:0x...` fails; use `dispatch 'hl.dsp.focus({ window = "address:0x..." })'`.
- **Window props are snake_case and renamed.** `opacity` not `alpha`, `border_size` not `bordersize`, `no_blur` not `forcenoblur`, `dim_around` not `dimaround`.
- **hyprpaper's config format changed.** `wallpaper = DP-1, /path` is silently ignored. `preload = /path` stays a plain keyword, but `wallpaper` is now a block taking exactly `monitor` and `path` (an empty `monitor` means every output).
- **hyprpaper's IPC changed to a binary protocol**, so `hyprctl hyprpaper preload ...` returns `invalid hyprpaper request`. Edit the config and restart the daemon.

When something doesn't behave, `Hyprland --verify-config`, `strings` on the binary, and the files under `/usr/share/hypr/` are more reliable than any guide.

## Building it yourself

Needs `podman` and [`just`](https://github.com/casey/just) (both on Bluefin already):

```bash
git clone https://github.com/holsee/bluefin-hyprland
cd bluefin-hyprland
just build                      # -> localhost/bluefin-hyprland:stable
podman run --rm localhost/bluefin-hyprland:stable rpm -q hyprland
```

## Forking

1. Edit `image-template.env` — `IMAGE_NAME`, `REPO_ORGANIZATION`.
2. In `build_files/build.sh`, update the repository name in the `policy.json` block; rename the two files under `system_files/` to match.
3. Generate a signing key and store the private half as the `SIGNING_SECRET` repository secret:
   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair
   gh secret set SIGNING_SECRET < cosign.key
   cp cosign.pub system_files/usr/lib/pki/containers/<org>-<image>.pub
   ```
   `cosign.key` is gitignored. Keep it that way.
4. Push. The workflow builds, pushes to `ghcr.io/<org>/<image>`, and signs the digest.

Add or remove packages in `build_files/build.sh`. Anything system-wide that isn't a package goes in `system_files/`, which is overlaid onto `/`.

## Acknowledgements

Built from [ublue-os/image-template](https://github.com/ublue-os/image-template). Hyprland packaging by [sdegler](https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/), ghostty packaging by [scottames](https://copr.fedorainfracloud.org/coprs/scottames/ghostty/). Desktop direction owes a lot to [Omarchy](https://omarchy.org).

## License

Apache-2.0, as inherited from the template.

## Snatch Studio

The image carries `snas`, `snasd`, `snas-app` and `snas-countdown` from the
latest release of [holsee/snatchstudio](https://github.com/holsee/snatchstudio)
(private). The build needs a `SNAS_TOKEN` repository secret, a PAT with
read access to that repo's releases; without it the stage is skipped and the
image still builds. Runtime packages (`wf-recorder`, `gtk4-layer-shell`,
`webkit2gtk4.1`, `libxkbcommon`) are layered either way.
