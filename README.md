# PVE Backup Manager

**Interactive, one-file backup scheduler for Proxmox VE.**
Pick your VMs and containers from a friendly text UI, choose a schedule, a retention policy and a destination (local disk, FTP, SFTP, Google Drive, S3 and more) - the installer does the rest and registers the cron job for you.

> Author: **Eren Akkuş** · License: MIT

---

## Features

- 🖥️ **Text-mode installer** (whiptail) with **Next / Back** navigation
- ✅ **Tick-box VM & LXC list** showing real names and status
- ⏰ **Flexible schedules**: hourly, every 2/3/4/6/8/12 hours, daily, Mon-Fri, weekly, monthly or any custom cron expression
- 🔢 **Retention**: keep the last *N* backups per VM/CT
- 🔀 **Order of cleanup**: *backup first, then delete old* (safe) or *delete oldest first, then backup* (saves space)
- 💾 **Local targets**: any Proxmox storage (disk, USB, NFS, CIFS...) or a custom directory
- ☁️ **Remote targets** via [rclone](https://rclone.org): FTP/FTPS, SFTP, Google Drive, OneDrive, Dropbox, Mega, S3-compatible (AWS, Wasabi, MinIO, Cloudflare R2...), Backblaze B2, WebDAV (Nextcloud/ownCloud) and any other rclone backend
- 📦 **One-by-one remote flow**: back up one VM → upload → verify → free local space → next VM (so you only need space for your largest single backup)
- 🔒 Lock file prevents overlapping runs, logs rotate monthly
- 🧹 Clean uninstall

## Requirements

- Proxmox VE 7 / 8 / 9 (run on the node, as `root`)
- `whiptail` (preinstalled on Proxmox)
- `rclone` - only for remote destinations (the installer offers to install it)

## Quick start

```bash
git clone https://github.com/erenakkus/pve-backup-manager.git
cd pve-backup-manager
chmod +x pve-backup-manager.sh
sudo ./pve-backup-manager.sh
```

Choose **Install / reconfigure scheduled backups** and follow the wizard.

## The wizard

| Step | What you choose |
|------|-----------------|
| 1 | VMs / containers to back up (SPACE to tick) |
| 2 | Schedule (hourly … monthly … custom cron) |
| 3 | How many backups to keep per VM/CT |
| 4 | Order: backup → delete old, or delete old → backup |
| 5 | Mode (snapshot / suspend / stop) and compression (zstd / gzip / lzo / none) |
| 6 | Destination type |
| 7 | Destination details (storage, path, credentials, connection test) |
| 8 | Summary → **Install** |

Use **Back** at any step to go to the previous one. Re-running the installer pre-fills your earlier answers.

## Schedules

| Option | Resulting cron |
|--------|----------------|
| Every hour | `M * * * *` |
| Every N hours (2, 3, 4, 6, 8, 12) | `M */N * * *` |
| Daily | `M H * * *` |
| Monday-Friday | `M H * * 1-5` |
| Weekly | `M H * * D` |
| Monthly (day 1-28) | `M H D * *` |
| Custom | your own 5-field expression |

The cron entry is written to `/etc/cron.d/pve-backup-manager`.

## Retention & cleanup order

- **Backup first, then delete old** - the new backup must succeed before anything is removed. Needs space for *N + 1* backups for a short time.
- **Delete oldest first, then backup** - frees space before the new backup is created, but if the backup fails you temporarily hold only *N − 1* backups. Use when disk space is tight.

Retention is applied **per VM/CT**.

## Destinations

| Destination | Notes |
|-------------|-------|
| Proxmox storage | Uses `vzdump --storage`; pruning via `pvesm`. Shows free space for each storage. |
| Custom directory | e.g. `/mnt/usb-backup`; checked for write access. |
| FTP / FTPS | Optional explicit TLS. |
| SFTP | Password or SSH key (the installer generates a key and shows the public key). |
| Cloud drives | Google Drive, OneDrive, Dropbox, Mega... via `rclone config` (the installer launches it for you). |
| S3-compatible | AWS, Wasabi, MinIO, Cloudflare R2, DigitalOcean Spaces, others. |
| Backblaze B2 | Application key ID + key. |
| WebDAV | Nextcloud, ownCloud, others. |

> **Google Drive on a headless server:** when `rclone config` asks *"Use web browser to automatically authenticate?"* answer **n**, run `rclone authorize "drive"` on a PC with a browser and paste the token back.

Credentials for remote targets are stored by rclone (obscured) in `/root/.config/rclone/rclone.conf`.

## What gets installed

| Path | Purpose |
|------|---------|
| `/usr/local/bin/pve-backup-run` | The backup runner executed by cron |
| `/etc/pve-backup-manager/pve-backup-manager.conf` | Your settings (root-only, no passwords) |
| `/etc/cron.d/pve-backup-manager` | The schedule |
| `/var/log/pve-backup-manager.log` | Log (rotated monthly) |
| `/etc/logrotate.d/pve-backup-manager` | Log rotation |

## Commands

```bash
sudo ./pve-backup-manager.sh              # interactive menu
sudo ./pve-backup-manager.sh --run        # run a backup right now
sudo ./pve-backup-manager.sh --uninstall  # remove cron job + runner
pve-backup-run                            # run the installed runner directly
tail -f /var/log/pve-backup-manager.log   # watch the log
```

## Restoring

Backups are standard `vzdump` archives.

```bash
# download from a remote first, if needed
rclone copy remote:proxmox-backups/node1/vzdump-qemu-100-2026_01_01-03_00_01.vma.zst /var/lib/vz/dump/

# VM
qmrestore /var/lib/vz/dump/vzdump-qemu-100-2026_01_01-03_00_01.vma.zst 100

# container
pct restore 101 /var/lib/vz/dump/vzdump-lxc-101-2026_01_01-03_00_01.tar.zst
```

## Good to know

- The VM list covers the **node you run the script on**. In a cluster, run the installer on each node.
- SFTP via rclone does not pin the server host key by default; prefer trusted networks or a VPN for FTP/SFTP targets, and use FTPS where possible.
- A failed upload keeps the local file in the staging folder until the next run of that VM.
- Always **test a restore** - an untested backup is only a hope.

## Uninstall

```bash
sudo ./pve-backup-manager.sh --uninstall
```

Existing backup files, the rclone package and your rclone remotes are never touched.

## Contributing

Issues and pull requests are welcome. Ideas: eren@resyst.com.tr, Proxmox Backup Server target, bandwidth limits, encryption (`rclone crypt`).

## Türkçe Özet

**PVE Backup Manager**, Proxmox VE için tek dosyalık, etkileşimli yedekleme kurulum aracıdır.

1. `sudo ./pve-backup-manager.sh` komutunu çalıştırın.
2. Açılan ekranda VM/CT'leri tikleyin, **Next** ile ilerleyin (**Back** ile geri dönebilirsiniz).
3. Zamanlamayı seçin: saatlik, günlük, haftalık, aylık veya özel cron.
4. Kaç yedek tutulacağını ve sıralamayı seçin: *yedek al → eskiyi sil* veya *eskiyi sil → yedek al*.
5. Hedefi seçin: yerel disk/dizin, FTP, SFTP, Google Drive, OneDrive, Dropbox, S3, Backblaze B2, WebDAV...
6. **Install** deyin; cron kaydı otomatik eklenir (`/etc/cron.d/pve-backup-manager`).

Uzak hedeflerde yedekler tek tek alınır: yedek → yükle → doğrula → yerel dosyayı sil → sıradaki VM.

## License

MIT © Eren Akkuş
