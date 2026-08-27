# KDE Plasma on Linux Mint — Migration Cheatsheet

## (Cinnamon → Plasma, kde-standard install)

### Install

- Install using `kde-standard`: `sudo apt install kde-standard`
- At the debconf prompt, choose `sddm` or `lightdm` (ssdm for ssdm themes).
- Reboot

### Quirks

If KDE can't locate check-language support, install it with `sudo apt install language-selector-common`.

*Remove snapd discovery in Discover*:

```bash
sudo apt purge plasma-discover-backend-snap
sudo apt autoremove --purge
```

*Vivaldi fix from Gnome to KDE for keyring*:

Vivaldi might spit out a warning about decryption failing. To fix it, use `gnome-libsecret`.

```bash
vivaldi --password-store=gnome-libsecret
```

To make it permanent, edit `~/.local/share/applications/vivaldi-stable.desktop` and look for all the lines
beginning with the following:

`Exec=/usr/bin/vivaldi-stable [...]`

and change them to:

`Exec=/usr/bin/vivaldi-stable --password-store=gnome-libsecret [....]`

Finally run: `update-desktop-database ~/.local/share/applications/`

*IP address plasmoid: missing QtPositioning/QtLocation*:

```bash
sudo apt install qml-module-qtpositioning qml-module-qtlocation
kquitapp5 plasmashell && kstart5 plasmashell   # restart to reload
```

### SDDM

#### Install manually

```bash
sudo tar -xzf /tmp/sugar-candy.tar.gz -C /usr/share/sddm/themes/
ls /usr/share/sddm/themes/                      # confirm + get folder name
# Preview before committing:
sddm-greeter --test-mode --theme /usr/share/sddm/themes/sugar-candy
# Set active:
sudo mkdir -p /etc/sddm.conf.d/
echo -e "[Theme]\nCurrent=sugar-candy" | sudo tee /etc/sddm.conf.d/theme.conf
# Check which display manager is active:
cat /etc/X11/default-display-manager
```
