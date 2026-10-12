# General Linux Commands

Saves tree output to a dated file.

```bash
tree > ~/music-library-$(date +%Y%m%d).txt
```

*MKVtools*:

Get information about tracks:

```bash
mkvmerge -i <filename>
```

The output will look something like this:

```bash
File 'filename.mkv': container: Matroska
Track ID 0: video (MPEG-1/2)
Track ID 1: audio (AC-3)
Track ID 2: subtitles (VobSub)
Chapters: 6 entries
```

Then extract the subs like this, using the track ID from above:

```bash
# VobSub extraction creates TWO files: filename.en.idx + filename.en.sub — keep them paired
mkvextract tracks "filename.mkv" <ID>:"filename.en.idx"
```

Set default audio tracks:

```bash
# track:a<#> = audio, track:v<#> = video, track:s<#> = subtitle
mkvpropedit "filename.mkv" --edit track:a1 --set flag-default=1 --edit track:a2 --set flag-default=0 
```

Set name of audio track:

```bash
# track:a<#> = audio, track:v<#> = video, track:s<#> = subtitle
mkvpropedit "filename.mkv" --edit track:a<#> --set name="English"  
```

You can use `mkvtoolnix-gui` for a GUI experience.

Switch from ssdm:

```bash
# check what you're actually on right now
cat /etc/X11/default-display-manager
systemctl status display-manager --no-pager | head -3

# make sure Mint's greeter stack is present before you switch
sudo apt install --reinstall lightdm lightdm-settings slick-greeter

# re-run the chooser — pick lightdm in the ncurses menu
sudo dpkg-reconfigure lightdm
```

Configure `sudo` to never ask for a password:

See the [askubuntu](https://askubuntu.com) answer right here: `https://askubuntu.com/a/147265`

```shell
#
# This file MUST be edited with the 'visudo' command as root.
#
# Please consider adding local content in /etc/sudoers.d/ instead of
# directly modifying this file.
#
# See the man page for details on how to write a sudoers file.
#
Defaults    env_reset
Defaults    mail_badpass
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

# Host alias specification

# User alias specification

# Cmnd alias specification

# User privilege specification
root    ALL=(ALL:ALL) ALL

# Members of the admin group may gain root privileges
%admin ALL=(ALL) ALL

# Allow members of group sudo to execute any command
%sudo   ALL=(ALL:ALL) ALL

# See sudoers(5) for more information on "#include" directives:

#includedir /etc/sudoers.d

YOUR_USERNAME_HERE ALL=(ALL) NOPASSWD: ALL
```

Create, modify, and delete groups:

See: `https://www.redhat.com/en/blog/linux-groups`.

-Create group: `sudo groupadd demo`
-Create group with specific gid: `sudo groupadd -g 1009 demo1`
-Change the gid: `sudo groupmod -g 1011 demo1`
-Rename a group: `sudo groupmod -n test demo1`
-Add user to a group: `sudo usermod --append --groups demo user1` or `sudo usermod -aG demo user2`
-Remove user from a group: `sudo gpasswd --delete user1 demo`
-Delete a group: `sudo groupdel demo`

Passwords:

-Change your password: `sudo passwd`
-Change user password: `sudo passwd {userNameHere}`
-Remove password for user: `sudo passwd -d jerry` or `sudo passwd --delete jerry`
-Lock and unlock changes: `sudo passwd -l {username}` and `sudo passwd -u {username}`

Create additional user on EC2 instance:

See: `https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/managing-users.html`.

## Rclone Mounting

Find mounted drives in rclone:

```bash
findmnt -t fuse.rclone
```

Unmount it:

```bash
fusermount -u /path/to/mountpoint
```

Check for rclone process:

```bash
pgrep -a rclone
```

Examples:

```bash
rclone mount --allow-other --allow-non-empty --uid 1000 --gid 1003 --default-permissions --vfs-cache-mode full --vfs-refresh --dir-cache-time 8760h --poll-interval 1m --vfs-cache-poll-interval 1m --vfs-cache-max-age 9999h --cache-dir <path/to/cache> --vfs-cache-max-size 50G google-drive:<path/to/remote> <path/to/local> &

rclone mount --allow-other --allow-non-empty --uid 1000 --gid 1003 --default-permissions --poll-interval 1m google-drive:<path/to/remote> <path/to/local> &

@reboot rclone mount --allow-other --allow-non-empty --default-permissions gdrive:<path/to/remote> <path/to/local> &
```

## Fstab

Editing and reloading:

```bash
sudo cp /etc/fstab /etc/fstab.bak          # backup first, always
sudo nano /etc/fstab                        # make the edit
sudo systemctl daemon-reload                # systemd builds mount units from fstab
sudo umount </path/to/drive>
sudo mount -a                               # remount with the new options
ls -ld </path/to/drive>   # should show drwxrwxr-x katy media
```

## Jellyfin

Shutdown, backup, and update Jellyfin

```bash
sudo systemctl stop jellyfin
sudo cp -p /var/lib/jellyfin/data/jellyfin.db /mnt/storage/katy/jellyfin-db-GOOD-511eps-$(date +%Y%m%d-%H%M).db
sudo chown katy:katy /mnt/storage/katy/jellyfin-db-GOOD-*.db
sudo apt install --only-upgrade --no-install-recommends "^jellyfin" 
```
