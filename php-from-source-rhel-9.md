# PHP from Source on RHEL 9 — Cheat Sheet

Oct 21, 2026 · @Katherine

## Overview

PHP is built from source into its own versioned folder under `/opt/php`, side by side with the RHEL AppStream RPMs, which stay installed as the rollback route. Apache needs no changes because the new FPM listens on the same socket as the packaged one.

```text
/opt/php/
├── 8.2.35/              ← one folder per build (bin/, sbin/, lib/, etc/)
│   └── etc/
│       ├── php.ini        ← copied from /etc/php.ini
│       ├── php-fpm.conf   ← small master config
│       ├── conf.d/        ← 10-opcache.ini
│       └── php-fpm.d/     ← www.conf pool
└── current -> 8.2.35    ← everything else points here
```

| Piece | Path |
| --- | --- |
| Source tree | `/root/php-8.2.35` |
| FPM service | `php-fpm-src.service` |
| FPM socket | `/run/php-fpm/www.sock` (same as RPM) |
| FPM log | `/var/log/php-fpm/error.log` |
| CLI on PATH | `/etc/profile.d/php-src.sh` |
| Old PHP (rollback) | RPMs: `php-fpm.service`, `/usr/bin/php` |

Trade-off: dnf no longer patches this PHP. Every security release means repeating the build. PHP 8.2 reaches end of life on 31 December 2026.

## 1. Download and verify

Change `V` to the version you want. Check the signature before building anything.

```bash
V=8.2.35
cd /root

# --proto '=https' forces HTTPS, including on redirects
curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
  --output php-$V.tar.xz "https://www.php.net/distributions/php-$V.tar.xz"
curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
  --output php-$V.tar.xz.asc "https://www.php.net/distributions/php-$V.tar.xz.asc"

# Release manager keys: https://www.php.net/gpg-keys.php
gpg --verify php-$V.tar.xz.asc php-$V.tar.xz   # want "Good signature"

tar -xJf php-$V.tar.xz
```

## 2. Record what you have now

The module list is the checklist the new build must match.

```bash
php -m > ~/php-modules-before.txt

mkdir -p ~/php-config-backup
cp -a /etc/php.ini /etc/php.d /etc/php-fpm.d ~/php-config-backup/
```

## 3. Build dependencies

Everything here comes from BaseOS, AppStream or CodeReady Builder. No EPEL or remi needed.

```bash
# Compiler toolchain: gcc, make, autoconf, bison
dnf groupinstall "Development Tools"

dnf install \
  libxml2-devel sqlite-devel openssl-devel libcurl-devel zlib-devel \
  oniguruma-devel libzip-devel libicu-devel \
  libpng-devel libjpeg-turbo-devel freetype-devel \
  systemd-devel bzip2-devel libxslt-devel gettext-devel libedit-devel
```

| Package | Needed for |
| --- | --- |
| `oniguruma-devel` | mbstring (CodeReady Builder) |
| `libzip-devel` | zip (CodeReady Builder) |
| `libicu-devel` | intl |
| `libpng` / `libjpeg-turbo` / `freetype-devel` | gd |
| `systemd-devel` | FPM `Type=notify` |
| `bzip2-devel` | bz2 |
| `libxslt-devel` | xsl |
| `gettext-devel` | gettext |
| `libedit-devel` | readline (via libedit, as Red Hat does) |
| `libacl-devel` | only if building `--with-fpm-acl` |

## 4. Configure, build, compare

These flags reproduce the RHEL module set exactly. Modules not listed (ctype, dom, fileinfo, iconv, json, PDO, pdo\_sqlite, posix, session, tokenizer, xml…) are built in by default.

```bash
cd /root/php-$V
PREFIX=/opt/php/$V

./configure \
  --prefix="$PREFIX" \
  --with-config-file-path="$PREFIX/etc" \
  --with-config-file-scan-dir="$PREFIX/etc/conf.d" \
  --enable-fpm --with-fpm-user=apache --with-fpm-group=apache --with-fpm-systemd \
  --with-openssl --with-curl --with-zlib --with-bz2 --enable-ftp --enable-sockets \
  --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
  --enable-mbstring --enable-intl --with-gettext --with-xsl \
  --enable-gd --with-jpeg --with-freetype --enable-exif \
  --with-zip --enable-calendar \
  --enable-pcntl --enable-shmop --enable-sysvmsg --enable-sysvsem --enable-sysvshm \
  --with-libedit \
  --enable-opcache
# Ends with "Thank you for using PHP." A "Package 'x' not found" error
# means install the matching -devel package and re-run.

make -j"$(nproc)"
NO_INTERACTION=1 make test   # optional, 10–20 min

# Only "Zend OPcache" should differ at this stage (it loads from ini later)
sapi/cli/php -m | diff - ~/php-modules-before.txt
```

Tip: a built PHP remembers its flags. `php -i | grep 'Configure Command'` prints them for the next build.

## 5. Install and carry over config

```bash
make install                          # into /opt/php/$V only
ln -sfn /opt/php/$V /opt/php/current
P=/opt/php/current
mkdir -p $P/etc/conf.d $P/etc/php-fpm.d

# Reuse the tuned RPM config. Skip the rest of /etc/php.d:
# those files load .so modules that are now compiled in.
cp -p /etc/php.ini $P/etc/php.ini
cp -p /etc/php.d/10-opcache.ini $P/etc/conf.d/
cp -p /etc/php-fpm.d/www.conf $P/etc/php-fpm.d/www.conf

# Red Hat's pool uses ACLs; this build has no --with-fpm-acl
F=$P/etc/php-fpm.d/www.conf
sed -i -E 's/^(\s*listen\.acl_(users|groups)\s*=)/;\1/' $F
cat >> $F <<'EOF'

; socket permissions without ACLs
listen.owner = apache
listen.group = apache
listen.mode = 0660
EOF

# Small FPM master config
cat > $P/etc/php-fpm.conf <<'EOF'
[global]
pid = /run/php-fpm/php-fpm.pid
error_log = /var/log/php-fpm/error.log
include = /opt/php/current/etc/php-fpm.d/*.conf
EOF

$P/sbin/php-fpm --test --fpm-config $P/etc/php-fpm.conf   # want "test is successful"
```

## 6. systemd unit and the swap

One-time setup. The unit always runs whatever `/opt/php/current` points at.

```bash
cat > /etc/systemd/system/php-fpm-src.service <<'EOF'
[Unit]
Description=PHP FastCGI Process Manager (source build, /opt/php/current)
After=network.target
# Never run alongside the RPM php-fpm (same socket)
Conflicts=php-fpm.service
After=php-fpm.service

[Service]
Type=notify
ExecStart=/opt/php/current/sbin/php-fpm --nodaemonize --fpm-config /opt/php/current/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 $MAINPID
RuntimeDirectory=php-fpm
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
```

The swap, in explicit steps (about one second of downtime):

```bash
systemctl stop php-fpm                 # release the socket
ss -xlp | grep www.sock                # no output = free
systemctl start php-fpm-src
systemctl status php-fpm-src --no-pager

systemctl disable php-fpm              # boot into the new one
systemctl enable php-fpm-src
```

SELinux is disabled on this box (`ls -Z` shows `?`). If it is ever enforcing, label the binary: `semanage fcontext -a -t httpd_exec_t '/opt/php/[^/]+/sbin/php-fpm' && restorecon -Rv /opt/php`.

## 7. Command-line PHP

Root's PATH on this box has no `/usr/local/bin`, so a symlink there does nothing. A profile.d drop-in puts the new PHP first for login shells. One-time setup.

```bash
cat > /etc/profile.d/php-src.sh <<'EOF'
# Source-built PHP ahead of the RPM's /usr/bin/php. Delete to roll back.
case ":$PATH:" in
  *:/opt/php/current/bin:*) ;;
  *) PATH="/opt/php/current/bin:$PATH" ;;
esac
export PATH
EOF

. /etc/profile.d/php-src.sh && hash -r
which -a php        # /opt/php/current/bin/php first
```

profile.d does not reach cron or scripts with a hard-coded `#!/usr/bin/php`. Find them and use `/opt/php/current/bin/php` explicitly, or add `PATH=/opt/php/current/bin:/usr/bin:/bin` at the top of the crontab.

```bash
grep -rn -E 'php|drush' /etc/crontab /etc/cron.d/ /var/spool/cron/ 2>/dev/null
```

Never replace `/usr/bin/php`. It belongs to the `php-cli` RPM, a `dnf update` would overwrite it, and it is the rollback.

## 8. Verify

- [ ] `php -v` shows the new version
- [ ] `php -m | diff - ~/php-modules-before.txt` prints nothing
- [ ] `/opt/php/current/sbin/php-fpm -v` shows the new version
- [ ] `systemctl status php-fpm-src` is active, master process from `/opt/php/current`
- [ ] Site responds: `curl -skI https://localhost/ | grep -i x-powered-by`
- [ ] No new errors in `tail -f /var/log/php-fpm/error.log` while clicking around
- [ ] Cron jobs checked (section 7)
- [ ] After the next reboot, `php-fpm-src` came up on its own

## Gotchas and fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `dnf` fails on remi SSL errors | remi/EPEL unreachable over TLS (suspected TLS inspection) | Keep remi/EPEL as `*.repo.bak`, or `dnf config-manager --set-disabled remi-safe remi-modular remi` |
| Installed PHP isn't from remi | Packages tagged `module+el9` are RHEL AppStream | AppStream updates need no remi; `dnf module list php` shows its streams |
| `make: command not found` | Toolchain not installed; configure also failed | `dnf groupinstall "Development Tools"`, then re-run configure |
| `unknown entry 'listen.acl_users'` | Red Hat's `www.conf` uses ACLs; build lacks `--with-fpm-acl` | Comment out the ACL lines, use `listen.owner/group/mode` |
| `Another FPM instance seems to already listen` | `Conflicts=` doesn't wait for the old FPM to stop | Stop `php-fpm` first; `After=php-fpm.service` in the unit |
| Site down after a failed start | `Conflicts=` stopped the RPM FPM | `systemctl start php-fpm` straight away |
| `php -v` still shows old version | `/usr/local/bin` not on root's PATH | `/etc/profile.d/php-src.sh` |
| `ls -Z` shows `?` | SELinux disabled | No labelling needed |

## Rollback

Back to the RPM PHP in under a minute. Nothing under `/usr` was touched.

```bash
systemctl stop php-fpm-src && systemctl start php-fpm
systemctl disable php-fpm-src && systemctl enable php-fpm
rm /etc/profile.d/php-src.sh     # then log out and back in
php -v                           # RPM version again
```

To roll back to an earlier source build instead, point the symlink back and restart: `ln -sfn /opt/php/<old> /opt/php/current && systemctl restart php-fpm-src`.
