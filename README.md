# PVE Backup Manager

> 🇹🇷 **Bu belge iki dillidir: önce Türkçe, ardından İngilizce.** İngilizce bölüme gitmek için [buraya tıklayın](#english).
> 🇬🇧 **This document is bilingual: Turkish first, then English.** [Jump to the English version](#english).

---

# Türkçe

**Proxmox VE için etkileşimli, tek dosyalık yedekleme zamanlayıcısı.**
VM ve konteynerlerinizi kullanışlı bir metin arayüzünden seçin, zamanlamayı, saklama politikasını ve hedefi (yerel disk, FTP, SFTP, Google Drive, S3 ve daha fazlası) belirleyin. Gerisini kurulum aracı halleder ve cron kaydını sizin yerinize ekler.

> Yazar: **Eren Akkuş** · Lisans: MIT

## Özellikler

- 🖥️ **Metin tabanlı kurulum ekranı** (whiptail), **Next / Back** ile ileri-geri gezinme
- ✅ **Tikli VM ve LXC listesi**, gerçek isimleri ve durumlarıyla
- ⏰ **Esnek zamanlama**: saatlik, 2/3/4/6/8/12 saatte bir, günlük, hafta içi, haftalık, aylık veya özel cron ifadesi
- 🔢 **Saklama**: her VM/CT için son *N* yedeği tut
- 🔀 **Temizlik sırası**: *önce yedek al, sonra eskiyi sil* (güvenli) veya *önce eskiyi sil, sonra yedek al* (yer kazandırır)
- 💾 **Yerel hedefler**: herhangi bir Proxmox storage (disk, USB, NFS, CIFS...) veya özel bir dizin
- ☁️ [rclone](https://rclone.org) ile **uzak hedefler**: FTP/FTPS, SFTP, Google Drive, OneDrive, Dropbox, Mega, S3 uyumlu servisler (AWS, Wasabi, MinIO, Cloudflare R2...), Backblaze B2, WebDAV (Nextcloud/ownCloud) ve diğer tüm rclone backend'leri
- 📦 **Uzak hedefte tek tek akış**: bir VM'i yedekle → yükle → doğrula → yerel alanı boşalt → sıradaki VM (yani yalnızca en büyük tek yedeğiniz kadar boş yer yeterli)
- 🔒 Kilit dosyası çakışan çalıştırmaları engeller, loglar aylık döndürülür
- 🧹 Temiz kaldırma

## Gereksinimler

- Proxmox VE 7 / 8 / 9 (node üzerinde, `root` olarak çalıştırın)
- `whiptail` (Proxmox'ta hazır gelir)
- `rclone` - yalnızca uzak hedefler için (kurulum aracı yüklemeyi teklif eder)

## Hızlı başlangıç

```bash
git clone https://github.com/erenakkus/proxmox-backup-wizard.git
cd proxmox-backup-wizard
chmod +x pve-backup-manager.sh
sudo ./pve-backup-manager.sh
```

**Install / reconfigure scheduled backups** seçeneğini seçin ve sihirbazı takip edin.

## Sihirbaz

| Adım | Seçtikleriniz |
|------|---------------|
| 1 | Yedeklenecek VM / konteynerler (tiklemek için SPACE) |
| 2 | Zamanlama (saatlik … aylık … özel cron) |
| 3 | Her VM/CT için kaç yedek saklanacağı |
| 4 | Sıra: yedek → eskiyi sil veya eskiyi sil → yedek |
| 5 | Mod (snapshot / suspend / stop) ve sıkıştırma (zstd / gzip / lzo / yok) |
| 6 | Hedef türü |
| 7 | Hedef ayrıntıları (storage, yol, kimlik bilgileri, bağlantı testi) |
| 8 | Özet → **Install** |

Herhangi bir adımda **Back** ile önceki adıma dönebilirsiniz. Kurulum aracını tekrar çalıştırdığınızda önceki cevaplarınız hazır gelir.

## Zamanlama

| Seçenek | Oluşan cron |
|---------|-------------|
| Her saat | `M * * * *` |
| N saatte bir (2, 3, 4, 6, 8, 12) | `M */N * * *` |
| Günlük | `M H * * *` |
| Pazartesi-Cuma | `M H * * 1-5` |
| Haftalık | `M H * * D` |
| Aylık (ayın 1-28. günü) | `M H D * *` |
| Özel | kendi 5 alanlı ifadeniz |

Cron kaydı `/etc/cron.d/pve-backup-manager` dosyasına yazılır.

## Saklama ve temizlik sırası

- **Önce yedek al, sonra eskiyi sil** - yeni yedek başarılı olmadan hiçbir şey silinmez. Kısa bir süre için *N + 1* yedek kadar yer gerekir.
- **Önce eskiyi sil, sonra yedek al** - yeni yedek oluşmadan önce yer açar. Ancak yedek başarısız olursa geçici olarak yalnızca *N − 1* yedeğiniz kalır. Disk alanı kısıtlıysa kullanın.

Saklama sayısı **her VM/CT için ayrı** uygulanır.

## Hedefler

| Hedef | Notlar |
|-------|--------|
| Proxmox storage | `vzdump --storage` kullanır; temizlik `pvesm` ile yapılır. Her storage'ın boş alanını gösterir. |
| Özel dizin | Örn. `/mnt/usb-backup`; yazma izni kontrol edilir. |
| FTP / FTPS | İsteğe bağlı explicit TLS. |
| SFTP | Parola veya SSH anahtarı (kurulum aracı anahtar üretir ve açık anahtarı gösterir). |
| Bulut diskler | Google Drive, OneDrive, Dropbox, Mega... `rclone config` ile (kurulum aracı sizin için başlatır). |
| S3 uyumlu | AWS, Wasabi, MinIO, Cloudflare R2, DigitalOcean Spaces ve diğerleri. |
| Backblaze B2 | Application key ID + key. |
| WebDAV | Nextcloud, ownCloud ve diğerleri. |

> **Başsız (ekransız) sunucuda Google Drive:** `rclone config` *"Use web browser to automatically authenticate?"* diye sorduğunda **n** cevabını verin, tarayıcısı olan bir bilgisayarda `rclone authorize "drive"` komutunu çalıştırın ve çıkan token'ı buraya yapıştırın.

Uzak hedeflerin kimlik bilgileri rclone tarafından (gizlenmiş olarak) `/root/.config/rclone/rclone.conf` dosyasında saklanır.

## Neler kurulur

| Yol | Amaç |
|-----|------|
| `/usr/local/bin/pve-backup-run` | Cron tarafından çalıştırılan yedekleme betiği |
| `/etc/pve-backup-manager/pve-backup-manager.conf` | Ayarlarınız (yalnızca root okur, parola içermez) |
| `/etc/cron.d/pve-backup-manager` | Zamanlama |
| `/var/log/pve-backup-manager.log` | Log (aylık döndürülür) |
| `/etc/logrotate.d/pve-backup-manager` | Log döndürme ayarı |

## Komutlar

```bash
sudo ./pve-backup-manager.sh              # etkileşimli menü
sudo ./pve-backup-manager.sh --run        # hemen bir yedek çalıştır
sudo ./pve-backup-manager.sh --uninstall  # cron kaydını ve betiği kaldır
pve-backup-run                            # kurulu betiği doğrudan çalıştır
tail -f /var/log/pve-backup-manager.log   # logu canlı izle
```

## Geri yükleme

Yedekler standart `vzdump` arşivleridir.

```bash
# gerekirse önce uzak hedeften indirin
rclone copy remote:proxmox-backups/node1/vzdump-qemu-100-2026_01_01-03_00_01.vma.zst /var/lib/vz/dump/

# VM
qmrestore /var/lib/vz/dump/vzdump-qemu-100-2026_01_01-03_00_01.vma.zst 100

# konteyner
pct restore 101 /var/lib/vz/dump/vzdump-lxc-101-2026_01_01-03_00_01.tar.zst
```

## Bilinmesi gerekenler

- VM listesi, scripti çalıştırdığınız **node'u** kapsar. Cluster'da kurulum aracını her node'da ayrı çalıştırın.
- rclone ile SFTP, varsayılan olarak sunucu host anahtarını sabitlemez. FTP/SFTP hedeflerinde güvenilir ağları veya VPN'i tercih edin, mümkünse FTPS kullanın.
- Başarısız bir yükleme, o VM'in bir sonraki çalıştırmasına kadar yerel dosyayı staging klasöründe bırakır.
- Geri yüklemeyi mutlaka **test edin** - denenmemiş bir yedek yalnızca bir umuttur.

## Kaldırma

```bash
sudo ./pve-backup-manager.sh --uninstall
```

Mevcut yedek dosyalarına, rclone paketine ve rclone remote'larınıza dokunulmaz.

## Katkı

Issue ve pull request'ler memnuniyetle karşılanır. Fikirler: e-posta / Telegram bildirimleri, Proxmox Backup Server hedefi, bant genişliği sınırı, şifreleme (`rclone crypt`).

## Lisans

MIT © Eren Akkuş

[⬆ Başa dön](#pve-backup-manager)

---

# English

> 🇹🇷 Türkçe sürüm yukarıdadır. [Türkçe bölüme dönmek için tıklayın](#türkçe).

**Interactive, one-file backup scheduler for Proxmox VE.**
Pick your VMs and containers from a friendly text UI, choose a schedule, a retention policy and a destination (local disk, FTP, SFTP, Google Drive, S3 and more) - the installer does the rest and registers the cron job for you.

> Author: **Eren Akkuş** · License: MIT

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
git clone https://github.com/erenakkus/proxmox-backup-wizard.git
cd proxmox-backup-wizard
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

Issues and pull requests are welcome. Ideas: e-mail / Telegram notifications, Proxmox Backup Server target, bandwidth limits, encryption (`rclone crypt`).

## License

MIT © Eren Akkuş

[⬆ Back to top](#pve-backup-manager)
