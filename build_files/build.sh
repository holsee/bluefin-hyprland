#!/bin/bash
# Runs inside the image build. Everything here ends up in the OS image.
set -ouex pipefail

# Static files: signing policy for this image's own key (see system_files/).
cp -avf /ctx/system_files/. /

# install_weak_deps=False throughout: the hyprland package *recommends* kitty,
# which would otherwise land in the image uninvited. We ship ghostty instead.
DNF="dnf5 -y install --setopt=install_weak_deps=False"

### Hyprland and its ecosystem
# Fedora dropped the hyprland package after F42. The sdegler COPR carries the
# compositor for F43/F44; the widely-documented solopasha COPR is dead (404).
dnf5 -y copr enable sdegler/hyprland
$DNF \
    hyprland hyprland-uwsm uwsm \
    xdg-desktop-portal-hyprland hyprpolkitagent \
    hyprlock hypridle hyprpaper \
    hyprshot hyprpicker hyprsunset \
    waybar cliphist satty nwg-look
dnf5 -y copr disable sdegler/hyprland

### Terminal — ghostty is not packaged in Fedora
dnf5 -y copr enable scottames/ghostty
$DNF ghostty
dnf5 -y copr disable scottames/ghostty

### Companions, all from Fedora proper
$DNF \
    fuzzel mako wlogout grim slurp \
    brightnessctl playerctl pavucontrol blueman \
    papirus-icon-theme qt6ct

### 1Password app + CLI — as RPMs, because the Flatpak has no SSH agent,
### browser integration or CLI integration.
# The app installs under /opt, which is a symlink to /var/opt and so not part
# of the image: give dnf a real /opt, move the app to /usr/lib/1Password, and
# tmpfiles.d links it back at boot.
# The scriptlets groupadd onepassword{,-cli,-mcp} only if missing; create them
# first from sysusers.d so file ownership matches the GIDs created at boot.
systemd-sysusers /usr/lib/sysusers.d/1password.conf
cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
rm /opt && mkdir /opt
$DNF 1password 1password-cli
mv /opt/1Password /usr/lib/1Password
rmdir /opt && ln -s /var/opt /opt
# The scriptlet writes this repo file back, enabled; leave it disabled like the COPRs.
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/1password.repo
# The polkit policy's owners (who may ask polkit on the SSH agent's and CLI's
# behalf) are filled from /etc/passwd at install, which is empty in a build.
sed 's/\${POLICY_OWNERS}/unix-user:holsee/' /usr/lib/1Password/com.1password.1Password.policy.tpl \
    > /usr/share/polkit-1/actions/com.1password.1Password.policy

### Snatch Studio (snas): screen capture and post-processing for this desktop.
# Runtime packages from Fedora; the binaries from the latest GitHub release
# of holsee/snatchstudio (private, so a token is needed; the secret is
# optional and the stage is skipped without it).
$DNF wf-recorder gtk4-layer-shell webkit2gtk4.1 libxkbcommon
if [ -s /run/secrets/github_token ]; then
    token=$(cat /run/secrets/github_token)
    api="https://api.github.com/repos/holsee/snatchstudio/releases/latest"
    asset_url=$(curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$api" \
        | python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin)["assets"] if x["name"].endswith(".tar.gz")]; print(a[0]["url"] if a else "")')
    if [ -n "$asset_url" ]; then
        curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/octet-stream" "$asset_url" -o /tmp/snas.tar.gz
        mkdir -p /tmp/snas && tar -xzf /tmp/snas.tar.gz -C /tmp/snas --strip-components=1
        PREFIX=/usr bash /tmp/snas/contrib/packaging/install.sh /tmp/snas
        rm -rf /tmp/snas /tmp/snas.tar.gz
    else
        echo "build.sh: no snatchstudio release asset found; skipping snas"
    fi
else
    echo "build.sh: no github_token secret; skipping snas"
fi

### Trust this image's own cosign key, so `bootc switch` / rpm-ostree rebase
### can verify signatures rather than falling through to the catch-all policy.
python3 - <<'PY'
import json
p = "/etc/containers/policy.json"
d = json.load(open(p))
d["transports"]["docker"]["ghcr.io/holsee/bluefin-hyprland"] = [{
    "type": "sigstoreSigned",
    "keyPath": "/usr/lib/pki/containers/holsee-bluefin-hyprland.pub",
    "signedIdentity": {"type": "matchRepository"},
}]
json.dump(d, open(p, "w"), indent=4)
print("policy.json: added ghcr.io/holsee/bluefin-hyprland")
PY

### bootc hygiene — /var and /run must be empty in the image.
# blueman's RPM ships /var/lib/blueman; it is recreated at boot by
# system_files/usr/lib/tmpfiles.d/bluefin-hyprland.conf instead.
rm -rf /var/lib/blueman
# dnf5 leaves repo metadata, a lock, and a runtime dir behind.
rm -rf /var/lib/dnf /run/dnf

# Sanity: the session entries GDM will offer must exist.
test -f /usr/share/wayland-sessions/hyprland.desktop
test -f /usr/share/wayland-sessions/hyprland-uwsm.desktop
# ...and 1Password's setgid helpers must carry the GIDs sysusers.d creates.
test "$(stat -c %g /usr/lib/1Password/1Password-BrowserSupport)" = 880
test "$(stat -c %g /usr/bin/op)" = 881
grep -q 'unix-user:holsee' /usr/share/polkit-1/actions/com.1password.1Password.policy
echo "build.sh: done"
