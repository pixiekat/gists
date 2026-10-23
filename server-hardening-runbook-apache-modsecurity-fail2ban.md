# Server Hardening Runbook: Apache, ModSecurity & fail2ban

Oct 11, 2026 · @Katherine

## Overview

No single lock is perfect, so every request passes several independent ones: the cloud firewall, Apache access rules, ModSecurity with the OWASP Core Rule Set, Anubis, and finally the app's own login. fail2ban watches the logs of all of them and turns repeat offenders into firewall bans, reported to AbuseIPDB.

&#91;embedded content: request layers · 5 locks, fail2ban watching 3\]

Apache, ModSecurity and Anubis all write logs that fail2ban reads; its bans land back at the firewall layer, before Apache ever sees the next request.

This runbook is written from the Hetzner box (Debian, Apache + PHP-FPM, Docker) and the work AWS box (Ubuntu). Each section has a short explanation, then a checklist to tick on a new server.

\*\*Refer to dotfiles and dotfiles-private for additional aliases and functions.

### Setup order on a new server

- [ ] 1\. Cloud firewall rule sets attached (section: Network firewall)
- [ ] 2\. Admin user, key-only SSH, password-gated sudo (section: Access)
- [ ] 3\. Apache baseline: catch-all vhost, redirects, loopback backends (section: Apache baseline)
- [ ] 4\. Geo access snippet on private sites (section: Geo access snippet)
- [ ] 5\. ModSecurity + CRS, audit log, custom rules (section: ModSecurity + CRS); checked out by tag for reference.
- [ ] 6\. Anubis in front of public sites (section: Anubis) \[Optional\]
- [ ] 7\. fail2ban jails, then AbuseIPDB reporting (sections: fail2ban, AbuseIPDB)
- [ ] 8\. Dotfiles helpers, backups, monitoring (sections: Helpers, Backups and monitoring)
- [ ] 9\. Run the verification checklist end to end

## Network firewall

Two reusable rule sets, attached together to every server: one for the world, one for admin access. Hetzner Cloud Firewalls and AWS security groups both combine attached sets as a union of allow rules, so if either set allows a port, it is open.

| Rule set | Ports | Source |
| --- | --- | --- |
| public-access | ICMP, TCP 80, TCP 443 | Any IPv4 / IPv6 |
| devops | TCP 22 (MySQL only if ever needed) | Trusted IPs only |

- Backend ports (Anubis backend 3006, app ports, databases) never appear in either set.
- Tailscale needs no inbound rule: it connects outward and uses relays if needed.
- Database access goes through an SSH tunnel (DBeaver) or the tailnet, never a public 3306.

Checklist:

- [ ] public-access holds only ICMP, 80, 443
- [ ] devops holds only 22, limited to trusted IPs
- [ ] Nothing like 3006, 3007 or 3306 in public-access
- [ ] From outside: `curl -sI --max-time 5 -H "Host: example.com" http://<server-ip>:3006/` times out

## Access: users, SSH and sudo

The goal is SSH by key only and sudo by password, so a stolen key alone never gives root.

```bash
# Create the admin user (no login password yet), then copy the cloud default user's groups
sudo adduser katherine --disabled-password
id ubuntu                                   # note its groups (adm, sudo, ...)
sudo usermod -aG adm,sudo katherine

# Authorise your key (on AWS, derive the public key from the .pem)
ssh-keygen -y -f /path/to/key-pair.pem      # paste into ~katherine/.ssh/authorized_keys

# Give the account a real password, used only to gate sudo
sudo passwd katherine
```

- `adm` lets you read `/var/log/apache2` without sudo, which the helper functions need.
- Edit sudoers only with `sudo visudo`; it syntax-checks before saving.
- Prefer `sudo -i` over `sudo su` for a root shell.

Rename the host so shell profiles can recognise it (AWS only needs the two extra steps):

```bash
echo "preserve_hostname: true" | sudo tee /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
sudo hostnamectl set-hostname dci-prod
# and add to /etc/hosts:   127.0.1.1   dci-prod
```

Checklist:

- [ ] `sudo passwd -S katherine` shows `P` (never `NP`)
- [ ] `sudo sshd -T | grep -i passwordauthentication` shows `no`
- [ ] `sudo -l -U katherine` shows `(ALL : ALL) ALL` with no `NOPASSWD`
- [ ] User is in `adm` (log access) and `sudo`
- [ ] Hostname survives a reboot; shell profile and prompt theme load for it
- [ ] Emergency path tested: Hetzner web console, or AWS SSM / serial console

## Apache baseline

Apache decides which requests reach anything at all: unknown hostnames hit a catch-all that refuses everything, and backend ports listen only on the loopback.

### Catch-all vhost

`/etc/apache2/sites-available/000-catchall.conf` must load first so it is the default server for :80 and :443.

```apache
<VirtualHost *:80>
    ServerName _
    ErrorLog ${APACHE_LOG_DIR}/catchall-error.log
    CustomLog ${APACHE_LOG_DIR}/catchall-access.log combined
    <Location />
        Require all denied
    </Location>
</VirtualHost>

<VirtualHost *:443>
    ServerName _
    ErrorLog ${APACHE_LOG_DIR}/catchall-error.log
    CustomLog ${APACHE_LOG_DIR}/catchall-access.log combined
    SSLEngine on
    Include /etc/letsencrypt/options-ssl-apache.conf
    # Snakeoil cert: a bare-IP scan learns none of your real domain names
    SSLCertificateFile    /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    <Location />
        Require all denied
    </Location>
</VirtualHost>
```

### Port 80 redirect vhosts

Use `mod_alias` and no `DocumentRoot`, so nothing can be served over plain HTTP even if the redirect breaks.

```apache
<VirtualHost *:80>
    ServerName dav.example.com
    Redirect permanent / https://dav.example.com/
</VirtualHost>
```

### Backend ports on the loopback only

```apache
# ports.conf: Anubis (host networking) forwards to 127.0.0.1:3006.
# <VirtualHost *:3006> blocks still match.
Listen 80
Listen 127.0.0.1:3006
```

Changing `Listen` needs a full `systemctl restart apache2`, not a reload.

### Reverse proxies

```apache
ProxyPreserveHost On
ProxyRequests Off
# ACME stays local; must come BEFORE the catch-all ProxyPass (first match wins)
ProxyPass "/.well-known/" "!"
# upgrade=websocket (Apache 2.4.47+) replaces all the old RewriteRule [P] blocks
ProxyPass / http://127.0.0.1:2283/ upgrade=websocket
ProxyPassReverse / http://127.0.0.1:2283/
# Large uploads (Immich): 2.4.53+ caps bodies at 1 GiB by default
LimitRequestBody 0
```

Use `127.0.0.1`, not `localhost`, for containers bound to IPv4 loopback.

### Serving and secrets

- Keep `.env`, `.git`, `CLAUDE.md`, `AGENTS.md` and `composer.json` above the docroot (`public/` or `web/`).
- Optional backstop, `/etc/apache2/conf-available/deny-dotfiles.conf`:

```
# /etc/apache2/conf-available/deny-dotfiles.conf
# Refuse any path segment starting with "." (.env, .git, .npmrc, .aws...)
# except /.well-known/, which ACME and other standards need.
# Exempt ACME and Anubis (its CSS, JS, images and honeypot live under /.within.website/)
<LocationMatch "/\.(?!well-known/|within\.website/)">
    Require all denied
</LocationMatch>
```

Checklist:

- [ ] `sudo apachectl -S | grep "default server"` lists the catch-all for :80 and :443
- [ ] Global ServerName set (`conf-available/servername.conf`) to silence AH00558
- [ ] Every :80 vhost is a bare `Redirect`, no `DocumentRoot`
- [ ] `sudo ss -tlnp | grep -E ':300[67]'` shows only `127.0.0.1:3006`
- [ ] Proxies use `upgrade=websocket` + `ProxyPassReverse` + `.well-known` exclusion
- [ ] Docroot is a subfolder; secrets and repo files sit above it
- [ ] Nothing else (e.g. `tailscale serve`) holds port 443; Tailscale serve moved to 8443

## Geo access snippet

Private sites (Jellyfin, Immich, Baikal, Audiobookshelf, Uptime Kuma, Matomo admin) share one include file, so allowlists change in one place. It uses `mod_maxminddb` with GeoLite2 databases in `/var/lib/GeoIP/`.

### Building and enabling mod\_maxminddb

The module is built from MaxMind's source release in `/root` (as on the Hetzner box), then loaded the Debian way with `a2enmod` and `a2enconf`. Check MaxMind's GitHub releases page for the current version number before downloading.

```bash
# Build dependencies: the MaxMind C library and Apache's apxs tool
sudo apt install libmaxminddb0 libmaxminddb-dev apache2-dev build-essential

# Build in /root, from the official release tarball
sudo -i
cd /root
VERSION=1.2.0    # replace with the current release
wget https://github.com/maxmind/mod_maxminddb/releases/download/${VERSION}/mod_maxminddb-${VERSION}.tar.gz
tar xzf mod_maxminddb-${VERSION}.tar.gz
cd mod_maxminddb-${VERSION}
./configure
make install     # uses apxs to copy mod_maxminddb.so into Apache's module dir
```

`make install` may also append a `LoadModule` line to `apache2.conf`. If it did, remove it there and use the Debian-style files below, so the module is loaded exactly once.

```apache
# /etc/apache2/mods-available/maxminddb.load
LoadModule maxminddb_module /usr/lib/apache2/modules/mod_maxminddb.so
```

```apache
# /etc/apache2/conf-available/maxminddb.conf
<IfModule mod_maxminddb.c>
    MaxMindDBEnable On
    MaxMindDBFile COUNTRY_DB /var/lib/GeoIP/GeoLite2-Country.mmdb
    MaxMindDBFile CITY_DB    /var/lib/GeoIP/GeoLite2-City.mmdb
</IfModule>
```

```bash
sudo a2enmod maxminddb
sudo a2enconf maxminddb
sudo apachectl configtest && sudo systemctl restart apache2
apachectl -M | grep maxminddb       # expect: maxminddb_module (shared)
```

The GeoLite2 databases come from a free MaxMind account and the `geoipupdate` tool:

```ini
# /etc/GeoIP.conf
AccountID <your-account-id>
LicenseKey <your-license-key>
EditionIDs GeoLite2-Country GeoLite2-City
DatabaseDirectory /var/lib/GeoIP
```

```bash
sudo apt install geoipupdate
sudo geoipupdate -v                 # first download
# Refresh: the Debian package runs geoipupdate from a systemd timer.
# Its /etc/cron.d/geoipupdate is a no-op fallback for non-systemd hosts;
# don't overwrite it. Check the timer and the file dates instead:
systemctl list-timers --all | grep -i geoip
ls -l /var/lib/GeoIP/               # dates within the last week = updating
```

Test a lookup the same way Apache will see it:

```bash
mmdblookup --file /var/lib/GeoIP/GeoLite2-City.mmdb --ip <an-ip> subdivisions 0 iso_code
```

- [ ] `apachectl -M` lists `maxminddb_module`, loaded once
- [ ] Both `.mmdb` files exist in `/var/lib/GeoIP/` and refresh on a schedule
- [ ] License key kept out of public repos (fits `dotfiles-private`)
- [ ] Rebuild the module after major Apache upgrades if Apache fails to start

`/etc/apache2/snippets/family-geo-access.conf`:

```apache
<IfModule mod_maxminddb.c>
    MaxMindDBEnv COUNTRY_CODE COUNTRY_DB/country/iso_code
    MaxMindDBEnv STATE_CODE   CITY_DB/subdivisions/0/iso_code
</IfModule>

<Location />
    # AND these rules with earlier ones (Directory, .htaccess) instead of
    # replacing them, so app denials like Matomo's /config still hold.
    AuthMerging And

    SetEnvIf COUNTRY_CODE ^(GB)$ AllowCountry

    <RequireAll>
        Require not ip 195.178.110.187
        <RequireAny>
            # Trusted IPs (family ISPs), internal Docker nets, this server
            Require ip 73.255.129.157 67.72.110.110
            Require ip 172.18.0.0/16 172.20.0.0/16
            Require ip 77.42.82.236
            Require env AllowCountry
            # US states: country AND state must both match
            Require expr "%{ENV:COUNTRY_CODE} == 'US' && %{ENV:STATE_CODE} =~ /^(MA|CT|RI|NH|VT|ME|FL|HI)$/"
        </RequireAny>
    </RequireAll>
</Location>

# Let's Encrypt must be reachable from anywhere. MUST come after
# <Location />: Location sections merge in file order, last one wins.
<Location /.well-known/acme-challenge/>
    Require all granted
</Location>
```

Use it inside each private vhost with `Include snippets/family-geo-access.conf`. Public exceptions go after the Include, for example Matomo's tracker:

```apache
<LocationMatch "^/((matomo|piwik)\.(php|js)$|js/)">
    Require all granted
</LocationMatch>
```

Why the US rule checks both fields: MaxMind's subdivision code drops the country prefix, so `NH` alone also matches Noord-Holland (Amsterdam), `CT`, `ME`, `RI` and `VT` match Italian provinces, and `MA` matches Malaga.

Checklist:

- [ ] Snippet included in every private vhost; public sites stay open
- [ ] ACME exception sits after `<Location />`; `sudo certbot renew --dry-run` passes for all certs
- [ ] Public exceptions (trackers, status pages) sit after the Include
- [ ] No `<Limit GET>` wrappers: rules apply to every method
- [ ] Denials appear as `AH01630` in the vhost error log
- [ ] Outside view checked with check-host.net or a non-allowed VPN exit

## ModSecurity + CRS

ModSecurity runs the OWASP Core Rule Set inside Apache and blocks a request once its anomaly score reaches 5 (paranoia level 1). Custom rules add zero-false-positive tripwires for things this server never serves.

```bash
sudo apt install libapache2-mod-security2 modsecurity-crs
sudo cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
```

In `/etc/modsecurity/modsecurity.conf`:

```apache
SecRuleEngine On
# Own folder, so it gets its own rotation rule (the Apache *.log glob skips subfolders)
SecAuditLog /var/log/apache2/modsec/modsec_audit.log
# A header, B request headers, F response headers, H rule messages, Z end.
# Drop E (response body) and K (every rule checked): they make entries huge.
SecAuditLogParts ABFHZ
```

```bash
sudo mkdir -p /var/log/apache2/modsec
sudo chown root:adm /var/log/apache2/modsec && sudo chmod 750 /var/log/apache2/modsec
```

`/etc/logrotate.d/modsec-audit` keeps 60 days:

```
/var/log/apache2/modsec/modsec_audit.log {
        daily
        missingok
        rotate 60
        compress
        delaycompress
        notifempty
        create 640 root adm
        postrotate
                if pgrep -f ^/usr/sbin/apache2 > /dev/null; then
                        invoke-rc.d apache2 reload 2>&1 | logger -t modsec.logrotate
                fi
        endscript
}
```

### Custom rules

Keep them in one file, IDs in ranges, with the scheme noted at the top. IDs must be unique across all loaded rules.

| ID | Catches | Action |
| --- | --- | --- |
| 9000100 | `Next-Action` header (Next.js Server Action probe) | deny 403 |
| 9000101 | `x-middleware-subrequest` (CVE-2025-29927 bypass) | deny 403 |
| 9000110 | `Go-http-client` user agent, except Cisco Umbrella 146.112.0.0/16 | deny 403 |
| 9000111 | `libredtail-http` user agent (RedTail cryptomining botnet: PHP-CGI CVE-2024-4577, PHPUnit eval-stdin) | deny 403 |
| 9000120 | Tencent fleet: `Connection: keep-alive, close` + iOS 13.2.3 UA | pass, log only (feeds the honeypot) |
| 1001 | Immich `/api/assets` uploads: body inspection off | pass |

```apache
# Custom rule ID ranges:
#   9000100-9000109  framework/app probes
#   9000110-9000119  scanner user agents
#   9000120-9000129  crawler fleet fingerprints

SecRule &REQUEST_HEADERS:x-middleware-subrequest "@gt 0" \
    "id:9000101,phase:1,deny,status:403,log,\
    msg:'Next.js middleware-bypass probe blocked (CVE-2025-29927)',\
    tag:'custom/next-middleware-bypass'"

SecRule REMOTE_ADDR "!@ipMatch 146.112.0.0/16" \
    "id:9000110,phase:1,deny,status:403,log,\
    msg:'Go default-UA scanner blocked',\
    tag:'custom/go-http-client-recon',chain"
    SecRule REQUEST_HEADERS:User-Agent "@beginsWith Go-http-client" "t:none"

# Phase 1 runs before Apache's access checks, so this fires even on the catch-all.
# No apostrophes inside msg:'...' (or escape them as \').
SecRule REQUEST_HEADERS:User-Agent "@beginsWith libredtail" \
    "id:9000111,phase:1,deny,status:403,log,\
    msg:'run away with your redtail between your legs',\
    tag:'custom/redtail-botnet'"

SecRule REQUEST_HEADERS:Connection "@rx \bkeep-alive,\s*close\b" \
    "id:9000120,phase:1,pass,log,\
    msg:'Tencent crawler fleet fingerprint',\
    tag:'custom/tencent-crawler',chain"
    SecRule REQUEST_HEADERS:User-Agent "@contains iPhone OS 13_2_3" "t:none"
```

Checklist:

- [ ] `SecRuleEngine On`, CRS loaded, `crs-setup.conf` matches the installed CRS version
- [ ] Audit log in `/var/log/apache2/modsec/`, parts `ABFHZ`, 60-day rotation
- [ ] `sudo logrotate -d /etc/logrotate.d/modsec-audit` parses cleanly
- [ ] Custom rules file has the ID-range header; `apachectl configtest` passes
- [ ] Test: `curl -s -o /dev/null -w '%{http_code}' https://site/.env` returns 403 and lands in the audit log
- [ ] Newest audit entry shows only sections A B F H Z

## Anubis

Anubis sits between Apache and the public sites: it challenges unknown clients, denies known-bad paths outright, and feeds crawlers word salad through hidden honeypot links. Flow: visitor to Apache :443, to Anubis on 127.0.0.1:9000, to the Apache backend on 127.0.0.1:3006.

```yaml
# docker/anubis/docker-compose.yml (relevant parts)
services:
  anubis:
    image: ghcr.io/techarohq/anubis:latest
    network_mode: host            # reaches the backend on 127.0.0.1
    environment:
      TARGET: "http://127.0.0.1:3006"
    logging:
      # journald: lines arrive unescaped and the container NAME stays
      # stable across recreations, so fail2ban can match it reliably
      driver: journald
```

- The bot policy (`botPolicy.yaml`) carries the deny rules, e.g. `wordpress-scanner-paths`, `known-shell-filenames`, `secret-file-probes`, `fake-ios13-zh-scraper`.
- Honeypot links live under `/.within.website/x/cmd/anubis/api/honeypot/`. Real people never see or follow them, so one hit means a bot.

Checklist:

- [ ] Anubis uses host networking and targets `127.0.0.1:3006`
- [ ] Backend port bound to loopback (see Apache baseline)
- [ ] Logging driver is journald: `sudo journalctl CONTAINER_NAME=anubis-anubis-1 -n 5`
- [ ] Fresh challenge works in a private window on each fronted site

## fail2ban

Each kind of visitor gets its own jail, so every ban has one owner and an honest report category. One file per jail in `/etc/fail2ban/jail.d/` keeps them easy to find and disable.

Modify to suit your own needs.

| Jail | Watches | Trigger | Ban | AbuseIPDB category |
| --- | --- | --- | --- | --- |
| apache-auth | Public sites' error logs | 5 Apache HTTP-auth failures (`ignoreregex` drops access denials) | default | 18 Brute-Force |
| apache-denied | Public sites' error logs | 5 `AH01630` / `AH01797` access-rule denials / 10m | 1d | 19, 21 |
| apache-geo | Private sites' + catch-all error logs | 5 `AH01630` denials / 10m | 1d | 19, 21 |
| drupal-auth | `/var/log/syslog` (Drupal syslog module) | 10 failed Drupal logins / 1h | 1h, doubling to 1w | 18 Brute-Force |
| apache-modsecurity | Error logs | Anomaly score exceeded | default | 21 |
| apache-goscanner | Error logs | Go-UA rule hit | default | 19, 21 |
| apache-noscript | Error logs | Script probes | default | 21 |
| anubis-honeypot | `/var/log/apache2/*access.log` | 1 honeypot hit / 1h | 1w | 19 |
| anubis-scanner | journald, Anubis container | 10 empty-UA challenges or denies / 60s | 1w | 19, 21 |
| canary-scanner | `*access.log` | 1 hit on `/z9x8c7v6b5-debug-trigger-` | 1w | 19, 21 |
| manual | none (hand bans) | `fail2ban-client set manual banip` | permanent, all ports | 19, 21 |
| recidive | fail2ban's own log | Repeat bans | long, all ports | default |

### Global settings

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
# Never ban yourself or shared security proxies (Cisco Umbrella)
ignoreip = 127.0.0.1/8 ::1 <home-ip> 146.112.0.0/16
```

```ini
# /etc/fail2ban/fail2ban.local: keep ban history so permanent bans restore
# Section name is case-sensitive: [Definition], never [DEFINITION]
[Definition]
dbpurgeage = 1y
```

### Filters

```ini
# filter.d/anubis-honeypot.conf
# fail2ban strips the timestamp BEFORE matching, so skip loosely to the request.
[Definition]
failregex = ^<HOST> -[^"]*"(?:GET|HEAD) /\.within\.website/x/cmd/anubis/api/honeypot/
```

```ini
# filter.d/canary-scanner.conf
[Definition]
failregex = ^<HOST> -[^"]*"(?:GET|HEAD) /z9x8c7v6b5-debug-trigger-
```

```ini
# filter.d/anubis-scanner.conf (journald lines are plain JSON)
[Definition]
failregex = "msg":"explicit deny".*"x-real-ip":"<HOST>"
            "msg":"new challenge issued".*"user_agent":"".*"x-real-ip":"<HOST>"
```

```ini
# jail.d/anubis-scanner.local
[anubis-scanner]
enabled      = true
filter       = anubis-scanner
backend      = systemd
journalmatch = CONTAINER_NAME=anubis-anubis-1
maxretry     = 10
findtime     = 60
bantime      = 1w
```

```ini
# jail.d/apache-geo.local (reuses the stock apache-auth filter)
[apache-geo]
enabled  = true
filter   = apache-auth
logpath  = /var/log/apache2/funcoland*error.log
           /var/log/apache2/immich*error.log
           /var/log/apache2/dav*error.log
           /var/log/apache2/audiobookshelf*error.log
           /var/log/apache2/uptime*error.log
           /var/log/apache2/analytics*error.log
           /var/log/apache2/catchall*error.log
port     = http,https
maxretry = 5
findtime = 10m
bantime  = 1d
```

### Access denials vs. logins

The stock `apache-auth` filter counts any "client denied by server configuration" line as a login failure. Once deny-dotfiles or `Require` rules exist, scanners hitting blocked paths get reported as Brute-Force. Split them: `apache-auth` keeps real HTTP-auth failures, and `apache-denied` owns access denials.

```ini
# jail.d/apache-auth.local
[apache-auth]
# AH01630 / AH01797 = an access rule refused the request (scanners, not
# logins). Match the words, not the code: the stock filter's prefregex
# strips "AH01630: " before failregex and ignoreregex see the line.
ignoreregex = client denied by server configuration
```

```ini
# filter.d/apache-denied.conf
[INCLUDES]
before = apache-common.conf

[Definition]
failregex = ^%(_apache_error_client)s (?:AH01630|AH01797): client denied by server configuration\b
ignoreregex =
```

```ini
# jail.d/apache-denied.local
[apache-denied]
enabled  = true
port     = http,https
filter   = apache-denied
logpath  = /var/log/apache2/*error.log
maxretry = 5
findtime = 10m
bantime  = 1d
action   = iptables-multiport[name=apache-denied, port="http,https", protocol=tcp]
           abuseipdb[abuseipdb_apikey=<key>, abuseipdb_category="19,21"]
```

If a server has no Apache HTTP auth at all (no `AH01617` / `AH01618` lines in its error logs), `apache-auth` has nothing left to catch and can simply be disabled.

### Drupal logins

Drupal logins never appear in Apache's logs as failures. Enable Drupal's syslog module (`drush en syslog -y`) and use the stock `drupal-auth` filter against syslog.

```ini
# jail.d/drupal-auth.local
[drupal-auth]
enabled  = true
port     = http,https
filter   = drupal-auth
logpath  = /var/log/syslog
# Debian/Ubuntu default to the systemd backend, which ignores logpath
backend  = auto
# Shared egress IPs (office NAT, Cisco Umbrella) must never be banned
ignoreip = 127.0.0.1/8 ::1 146.112.0.0/16 <office-egress-ips>
# Drupal flood control: 5 per account / 6h, 50 per IP / 1h
maxretry = 10
findtime = 1h
# Short first ban for confused humans, doubling for persistent bots.
# Needs dbpurgeage >= bantime.maxtime.
bantime  = 1h
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 1w
action   = iptables-multiport[name=drupal-auth, port="http,https", protocol=tcp]
           abuseipdb[abuseipdb_apikey=<key>, abuseipdb_category="18"]
```

Check that the matched IP is the real client, not `127.0.0.1` or a load balancer; behind a proxy, set `$settings['reverse_proxy']` in `settings.php`.

```ini
# jail.d/manual.local: hand-picked permanent bans
[manual]
enabled   = true
filter    = manual              ; empty failregex
logpath   = /var/log/fail2ban.log
banaction = %(banaction_allports)s
bantime   = -1
```

Back up manual bans to `dotfiles-private/fail2ban/manual-bans.txt` with `fail2ban-client get manual banip`, and restore with a `while read` loop of `banip`.

Checklist:

- [ ] Every jail tested first: `sudo fail2ban-regex <log> /etc/fail2ban/filter.d/<filter>.conf`
- [ ] journald jails tested with `fail2ban-regex "systemd-journal[journalmatch='CONTAINER_NAME=anubis-anubis-1']" <filter>`
- [ ] `python3-systemd` installed for the systemd backend
- [ ] apache-auth and apache-geo log lists do not overlap: `sudo fail2ban-client get <jail> logpath`
- [ ] New vhosts added to apache-auth (public) or apache-geo (private)
- [ ] `ignoreip` includes home IP and 146.112.0.0/16
- [ ] `dbpurgeage = 1y`; permanent bans survive `systemctl restart fail2ban`
- [ ] Manual bans exported to the backup list

## AbuseIPDB reporting

Reports only help others if they are accurate, and accurate reports keep your reporter standing good. Each jail reports with categories that describe what actually happened.

```ini
# Per jail, same style on every server (key redacted in shared configs)
action = iptables-multiport[name=apache-geo, port="http,https", protocol=tcp]
         abuseipdb[abuseipdb_apikey=<key>, abuseipdb_category="19,21"]
```

| Category | Use for |
| --- | --- |
| 18 Brute-Force | Real login or auth failures (public-site apache-auth) |
| 19 Bad Web Bot | Crawlers, honeypot hits, empty-UA scanners |
| 21 Web App Attack | Exploit, shell, `.env`, path probes |

- Comments use the short form `Banned by fail2ban (<jail>, <N> hits)`: no hostnames, paths or raw log lines in public reports.
- AbuseIPDB ignores repeat reports of one IP from you within 15 minutes, so overlapping jails only add noise.
- Confidence of Abuse weights recent reports: a quiet IP drops to 0% even with thousands of old reports. Judge a /24 by its recent offenders.
- Never report shared proxies (Cisco Umbrella 146.112.0.0/16); they carry many organisations' traffic.

Checklist:

- [ ] API key set in every reporting action, never committed to a public repo
- [ ] Categories per jail match the table above
- [ ] Comment format is the short form on every server
- [ ] Shared proxies in `ignoreip`, so they are neither banned nor reported

## Helper functions

Two functions in `.functions` (dotfiles) answer "what did this IP do?" across the current and rotated audit logs, old location included. They are only defined on machines that have an audit log.

```bash
# --- ModSecurity audit log helpers ------------------------------------------
# New location first, old location as fallback.
if [ -f "/var/log/apache2/modsec/modsec_audit.log" ]; then
    _MODSEC_AUDIT_LOG="/var/log/apache2/modsec/modsec_audit.log"
elif [ -f "/var/log/apache2/modsec_audit.log" ]; then
    _MODSEC_AUDIT_LOG="/var/log/apache2/modsec_audit.log"
else
    _MODSEC_AUDIT_LOG=""
fi

if [[ -f "$_MODSEC_AUDIT_LOG" ]]; then

    # Print every complete audit entry for one client IP, oldest first.
    # zcat -f reads .gz and plain files alike; awk dedupes the file list when
    # both globs match the same files; the IP is compared as an exact string
    # on field $4 of the A-section line, so 1.2.3.4 never matches 1.2.3.44.
    _modsec-entries-for-ip() {
        sudo bash -c 'zcat -f $(ls -1tr /var/log/apache2/modsec_audit.log* '"$_MODSEC_AUDIT_LOG"'* 2>/dev/null | awk '"'"'!seen[$0]++'"'"')' \
        | awk -v ip="$1" '
            /^--[0-9a-f]+-A--$/ { keep = 0; expect_a = 1; boundary = $0; next }
            expect_a            { expect_a = 0; if ($4 == ip) { keep = 1; print boundary } }
            keep                { print }
        '
    }

    # What did a given IP request?
    modsec-requests-by-ip() {
        [[ -z "$1" ]] && { echo "usage: modsec-requests-by-ip <ip>" >&2; return 1; }
        _modsec-entries-for-ip "$1" | grep -E '^[A-Z]+ [^ ]+ HTTP/[0-9.]+$'
    }

    # Which rules did a given IP trip? Message: lines only, so each hit counts once.
    modsec-rules-by-ip() {
        [[ -z "$1" ]] && { echo "usage: modsec-rules-by-ip <ip>" >&2; return 1; }
        _modsec-entries-for-ip "$1" | grep '^Message:' | grep -oP '\[id "\K\d+' | sort | uniq -c | sort -rn
    }
fi
```

Other handy one-liners:

```bash
# Who was denied most on a geo-locked site
grep AH01630 /var/log/apache2/funcoland.spacecadetgrrl.me-error.log \
  | grep -oP 'client \K[0-9.]+' | sort | uniq -c | sort -rn | head

# Live ban counters per jail
sudo watch -d -n 5 'iptables -L f2b-manual -v -n | head -n 8'
```

Checklist:

- [ ] User is in `adm`, or the `-f` checks fail and the functions are never defined
- [ ] `modsec-requests-by-ip <your server IP>` shows a test `/.env` request
- [ ] No doubled results on servers still using the old log path

## Backups and monitoring

Backups live in three places with snapshots the server cannot touch, and monitoring reaches your phone the moment something falls over.

- Nightly SQL dumps at 03:00 to the volume, 11-day rotation, pushed to two Hetzner Storage Boxes.
- Automatic snapshots on both Storage Boxes and the server: a compromised server holds the push credentials, but not the snapshots.
- Dumps contain password hashes and sessions, so lock them down:

```bash
chmod 700 /path/to/archives/sql_dumps
chmod 600 /path/to/archives/sql_dumps/*.tar.gz
# and add near the top of the dump script:
umask 077
```

- Uptime Kuma (127.0.0.1:3001, behind the geo snippet) alerts through ntfy.
- Kuma lives on the same server, so a full outage silences it: add an outside watcher (a second Kuma at home, a hosted pinger, or a heartbeat that alerts when pings stop).
- Optional: `etckeeper` puts `/etc` under git, so every config change has a history.

Checklist:

- [ ] Dump folder `700`, dumps `600`, `umask 077` in the script
- [ ] Off-server copy plus snapshots enabled on every Storage Box
- [ ] A test restore into a throwaway MariaDB container, every few months
- [ ] Uptime Kuma monitors every site; ntfy alerts arrive on the phone
- [ ] An outside watcher covers the case where the whole server is down

## Verification checklist

Run these after setup and after any big change; each line proves one layer works.

```bash
# Apache: config, default servers, listeners
sudo apachectl configtest
sudo apachectl -S | grep "default server"
sudo ss -tlnp | grep -E ':(443|8443|300[67]) '

# Backend not reachable from outside (run from your desktop: should time out)
curl -sI --max-time 5 -H "Host: example.com" http://<server-ip>:3006/

# ModSecurity blocks and logs (expect 403, then a new audit entry)
curl -s -o /dev/null -w '%{http_code}\n' https://<allowed-site>/.env
modsec-requests-by-ip <your-ip>

# Certificates renew through the ACME exceptions
sudo certbot renew --dry-run

# fail2ban: every jail running, filters match real lines
sudo fail2ban-client status
sudo fail2ban-regex /var/log/apache2/<site>-access.log /etc/fail2ban/filter.d/anubis-honeypot.conf

# Firewall chains and counters
sudo iptables -L -v -n | grep -A3 '^Chain f2b-'

# Access
sudo passwd -S katherine
sudo sshd -T | grep -i passwordauthentication
sudo -l -U katherine
```

- [ ] `Syntax OK`; catch-all is default on :80 and :443
- [ ] Only Apache on 443, Tailscale serve on 8443, backend on 127.0.0.1
- [ ] Port 3006 times out from outside
- [ ] `.env` test returns 403 and appears via the helper
- [ ] All certificate dry-run renewals succeed
- [ ] Each jail's filter matches at least one real line
- [ ] `P`, `passwordauthentication no`, no `NOPASSWD`
- [ ] Private sites load from home; check-host.net shows 403 elsewhere
- [ ] Websockets work: Jellyfin and Uptime Kuma show `101` for `/socket`

## Gotchas and lessons learned

Every item here cost real debugging time once; most fail silently.

| Gotcha | What happens | Fix |
| --- | --- | --- |
| MaxMind `STATE_CODE` alone | `NH` matches Noord-Holland, `MA` Malaga | Require `COUNTRY_CODE == 'US'` AND the state |
| `<Location>` merge order | Later section's `Require` replaces earlier, by file order not specificity | ACME and public exceptions go after the geo block |
| `<Location />` vs app `.htaccess` | Geo rules override Matomo's `/config` denials | `AuthMerging And` in the snippet |
| Stock apache-auth filter | Counts `AH01630` access denials as Brute-Force | ignoreregex for "client denied by server configuration" on apache-auth; apache-denied (public) and apache-geo (private) own denials |
| fail2ban timestamps | Date is stripped before `failregex` runs | Skip loosely: `-[^"]*"` |
| `fail2ban-regex` on a missing file | Tests the path text as a "single line" and reports 0 matches | Check the exact log filename first |
| journald backend | Jail only reads from start time, so earlier tests never count | Expected; fail2ban-regex reads the whole journal |
| iptables chains | Created on the first ban, not at jail start | Empty chain list is normal for a new jail |
| Docker `json-file` logs | Escaped quotes; path contains the container ID, which changes | Switch the container to the journald driver |
| `Listen 3006` on all interfaces + firewall rule | Anyone can bypass Anubis via `:3006` | `Listen 127.0.0.1:3006`, rule removed |
| `tailscale serve` on 443 | Apache fails to restart: address already in use | `tailscale serve --bg --https=8443 2283` |
| Two logrotate rules for one file | Duplicate entry error | Move the audit log to its own folder |
| `/var/log/apache2` is `750 root:adm` | `[[ -f ]]` fails for normal users; functions never defined | Add the user to `adm` |
| Variables in `sudo bash -c '...'` | Not expanded: root's shell never had them | Close the quote: `'...'"$VAR"'...'` |
| ModSecurity rule IDs | Reusing one fails configtest | Keep ID ranges; grep before adding |
| `passwd --delete` | Leaves an EMPTY password until reset | Always finish with `sudo passwd <user>` |
| AWS cloud-init | Resets hostname every boot | `preserve_hostname: true` |
| Shared proxy IPs (Cisco Umbrella) | One ban blocks a whole organisation | `ignoreip` + exempt from UA rules |
| Confidence of Abuse 0% | Old abusive IPs look clean | Judge /24 blocks by recent reports |

Left for later:

- [ ] Whole-ASN bans for abuse-tolerant hosts (AS48090 TECHOFF) via a monthly prefix refresh
- [ ] `iptables-ipset` ban action once jails hold hundreds of IPs
- [ ] Baikal invite email: disable it, or relay through msmtp on port 587
- [ ] Snakeoil cert on both catch-all vhosts
- [ ] Trim `.vimrc`, `.inputrc`, `split-show.sh` warnings from the dotfiles link script
