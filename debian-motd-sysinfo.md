# Debian login MOTD — system info at a glance

A `/etc/update-motd.d/` drop-in that greets you on login with the stuff you
actually want on a server: host/IP, load, uptime, memory, disk (root + data
volume), pending apt updates, and — the good part — kernel/service restart
state via `needrestart`, so a long-uptime box tells you when it needs a reboot.

Lives at `/etc/update-motd.d/20-sysinfo`, owned by root, `chmod +x`. These
scripts run **as root** at login, which matters for the optional hyfetch line.

```bash
#!/bin/bash
# /etc/update-motd.d/20-sysinfo
# Displays basic system information on login
# Sections: hostname/ip, load, uptime, memory, disk, apt updates, restarts

# --- :3 --- optional trans-flag banner. update-motd.d runs as ROOT, so hyfetch
# won't see your user's config unless you run it as your user explicitly:
# runuser -u katie -- hyfetch -p transgender

# --- Hostname and IP ---
# `ip route get` returns the address on the real egress interface, so a Docker
# or bridge IP (172.17.x.x) can't hijack it the way `hostname -I | awk '{print $1}'`
# can. Match on the `src` token rather than a fixed column, because the field
# position shifts depending on whether the route has a `via` gateway.
ip_addr=$(ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i+1); exit}}')
[ -z "$ip_addr" ] && ip_addr=$(hostname -I | awk '{print $1}')  # fallback
echo "Host: $(hostname)"
echo "IP:   $ip_addr"
echo ""

# --- Average Load ---
# /proc/loadavg has 5 fields; the last two are running/total processes and the
# last PID -- not load. Print only the 1/5/15-minute averages.
echo "Average Load: $(awk '{print $1, $2, $3}' /proc/loadavg)"
echo ""

# --- Uptime ---
echo "Uptime: $(uptime -p)"
echo ""

# --- CPU and Memory ---
echo "Memory: $(free -h | awk '/^Mem:/ {print $3 " used / " $2 " total"}')"
echo ""

# --- Disk Usage (root and data volume) ---
# NOTE: the volume mountpoint is host-specific -- change or drop it on other
# boxes. 2>/dev/null keeps df quiet if the path is absent so the section still
# prints root cleanly.
echo "Disk:"
df -h / /mnt/HC_Volume_105148208 2>/dev/null \
    | awk 'NR>1 {print "  " $6 " " $3 "/" $2 " (" $5 " used)"}'
echo ""

# --- Pending apt updates ---
# Prefer update-notifier's cached count (cheap); fall back to `apt list` so we
# never run a slow simulated upgrade on every single login.
if [ -r /var/lib/update-notifier/updates-available ]; then
    updates=$(awk '/packages can be (updated|upgraded)/ {print $1}' /var/lib/update-notifier/updates-available)
else
    updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable from")
fi
echo "Pending updates: $updates"
echo ""

# --- Pending restarts (kernel + services) ---
# needrestart -b (batch) exposes machine-readable status lines. KSTA is the
# kernel state; SVC lines are services still running old code.
if command -v needrestart >/dev/null 2>&1; then
    nr_output=$(needrestart -b 2>/dev/null)
    nr_ksta=$(echo "$nr_output" | awk -F': ' '/^NEEDRESTART-KSTA/ {print $2}')
    nr_svc=$(echo "$nr_output" | grep -c '^NEEDRESTART-SVC:')

    case "$nr_ksta" in
        1) kernel_msg="kernel up to date" ;;
        2) kernel_msg="kernel: ABI-compat upgrade pending" ;;
        3) kernel_msg="kernel: REBOOT RECOMMENDED" ;;
        *) kernel_msg="kernel status unknown" ;;
    esac

    if [ "$nr_svc" -gt 0 ]; then
        echo "Restarts needed: $kernel_msg, $nr_svc service(s)"
    else
        echo "Restarts needed: $kernel_msg"
    fi
    echo ""
fi
```

## Deploy

```bash
sudo install -m 0755 20-sysinfo /etc/update-motd.d/20-sysinfo
run-parts /etc/update-motd.d/   # preview what login will show
```

## Notes

- Requires `needrestart` for the restart section (`sudo apt install needrestart`); the block self-skips if it's
absent.
- The data-volume line is specific to this host's Hetzner Cloud volume — edit the mountpoint per box.
- `update-notifier`'s cached file is Ubuntu-flavored; on plain Debian it usually won't exist, so the
`apt list --upgradable` fallback is what runs.
