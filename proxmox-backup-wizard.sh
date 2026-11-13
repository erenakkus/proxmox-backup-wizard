#!/usr/bin/env bash
#
# PVE Backup Manager - interactive installer for scheduled Proxmox VE backups
#
# Author : Eren Akkuş
# License: MIT
#
# Usage  : sudo ./pve-backup-manager.sh            (interactive menu)
#          sudo ./pve-backup-manager.sh --run      (run a backup now)
#          sudo ./pve-backup-manager.sh --uninstall
#
set -o pipefail

VERSION="1.0.0"
APP="pve-backup-manager"
CONF_DIR="/etc/${APP}"
CONF_FILE="${CONF_DIR}/${APP}.conf"
RUNNER="/usr/local/bin/pve-backup-run"
CRON_FILE="/etc/cron.d/${APP}"
LOGROTATE_FILE="/etc/logrotate.d/${APP}"
LOG_FILE="/var/log/${APP}.log"
TITLE="PVE Backup Manager v${VERSION}"
BACKTITLE="PVE Backup Manager - by Eren Akkuş"
RC_NAME="pvebackup"

VMIDS=""
SCHED_KEY="daily"
CRON_EXPR=""
SCHED_DESC=""
KEEP=7
ORDER="backup_first"
MODE="snapshot"
COMPRESS="zstd"
DEST_KIND="local_storage"
DEST_TYPE="storage"
STORAGE=""
DIR=""
REMOTE_NAME=""
REMOTE_PATH=""
STAGING="/var/tmp/pve-backup-staging"
declare -A VMNAME=()
TIME_H=3
TIME_M=0

die() { echo "ERROR: $*" >&2; exit 1; }

msg() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox "$1" 16 74
}

ask_input() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --inputbox "$1" 12 74 "${2:-}" 3>&1 1>&2 2>&3
}

ask_pass() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --passwordbox "$1" 10 74 3>&1 1>&2 2>&3
}

oo() { [[ "$1" == "$2" ]] && echo ON || echo OFF; }

need_root() { [[ $EUID -eq 0 ]] || die "Please run as root (sudo)."; }

check_env() {
  for c in pvesm qm pct vzdump; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' not found - this does not look like a Proxmox VE host."
  done
  if ! command -v whiptail >/dev/null 2>&1; then
    echo "whiptail is missing, installing..."
    apt-get update -qq && apt-get install -y whiptail || die "Could not install whiptail."
  fi
}

load_existing() {
  if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
  fi
}

step_vms() {
  local items=() id name status out st
  VMNAME=()

  while read -r id name status; do
    [[ -n "$id" ]] || continue
    VMNAME[$id]="$name"
    st=OFF; [[ " $VMIDS " == *" $id "* ]] && st=ON
    items+=("$id" "VM  ${name} (${status})" "$st")
  done < <(qm list 2>/dev/null | awk 'NR>1 {print $1, $2, $3}')

  while read -r id name status; do
    [[ -n "$id" ]] || continue
    VMNAME[$id]="$name"
    st=OFF; [[ " $VMIDS " == *" $id "* ]] && st=ON
    items+=("$id" "CT  ${name} (${status})" "$st")
  done < <(pct list 2>/dev/null | awk 'NR>1 {print $1, $NF, $2}')

  if [[ ${#items[@]} -eq 0 ]]; then
    msg "No VMs or containers were found on this node."
    return 1
  fi

  out=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Exit" \
    --checklist "Select the VMs / containers to back up.\n\nSPACE = tick / untick,  ENTER = Next" \
    24 78 14 "${items[@]}" 3>&1 1>&2 2>&3) || return 1

  VMIDS=$(echo "$out" | tr -d '"')
  if [[ -z "${VMIDS// }" ]]; then
    msg "Please select at least one VM or container."
    return 2
  fi
  return 0
}

ask_time() {
  local t
  while true; do
    t=$(ask_input "At what time of day should the backup start?\n(24-hour format HH:MM, e.g. 03:30)" "${1:-03:00}") || return 1
    if [[ "$t" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
      TIME_H=$((10#${BASH_REMATCH[1]}))
      TIME_M=$((10#${BASH_REMATCH[2]}))
      return 0
    fi
    msg "Invalid time. Use HH:MM, for example 03:30"
  done
}

ask_minute() {
  local v
  while true; do
    v=$(ask_input "At which minute of the hour should it run? (0-59)" "0") || return 1
    if [[ "$v" =~ ^[0-9]+$ ]] && (( 10#$v >= 0 && 10#$v <= 59 )); then
      TIME_M=$((10#$v)); return 0
    fi
    msg "Enter a number between 0 and 59."
  done
}

hhmm() { printf '%02d:%02d' "$1" "$2"; }

step_schedule() {
  local key d day dname

  key=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "How often should the backup run?" 26 78 14 \
    hourly   "Every hour"                          "$(oo "$SCHED_KEY" hourly)" \
    every2h  "Every 2 hours"                       "$(oo "$SCHED_KEY" every2h)" \
    every3h  "Every 3 hours"                       "$(oo "$SCHED_KEY" every3h)" \
    every4h  "Every 4 hours"                       "$(oo "$SCHED_KEY" every4h)" \
    every6h  "Every 6 hours"                       "$(oo "$SCHED_KEY" every6h)" \
    every8h  "Every 8 hours"                       "$(oo "$SCHED_KEY" every8h)" \
    every12h "Every 12 hours (twice a day)"        "$(oo "$SCHED_KEY" every12h)" \
    daily    "Every day at a chosen time"          "$(oo "$SCHED_KEY" daily)" \
    weekdays "Monday to Friday at a chosen time"   "$(oo "$SCHED_KEY" weekdays)" \
    weekly   "Once a week (choose weekday + time)" "$(oo "$SCHED_KEY" weekly)" \
    monthly  "Once a month (choose day + time)"    "$(oo "$SCHED_KEY" monthly)" \
    custom   "Custom cron expression"              "$(oo "$SCHED_KEY" custom)" \
    3>&1 1>&2 2>&3) || return 1

  case "$key" in
    hourly)
      ask_minute || return 2
      CRON_EXPR="$TIME_M * * * *"
      SCHED_DESC="Every hour at minute $TIME_M" ;;
    every2h|every3h|every4h|every6h|every8h|every12h)
      d=${key#every}; d=${d%h}
      ask_minute || return 2
      CRON_EXPR="$TIME_M */$d * * *"
      SCHED_DESC="Every $d hours at minute $TIME_M" ;;
    daily)
      ask_time "03:00" || return 2
      CRON_EXPR="$TIME_M $TIME_H * * *"
      SCHED_DESC="Every day at $(hhmm "$TIME_H" "$TIME_M")" ;;
    weekdays)
      ask_time "03:00" || return 2
      CRON_EXPR="$TIME_M $TIME_H * * 1-5"
      SCHED_DESC="Monday-Friday at $(hhmm "$TIME_H" "$TIME_M")" ;;
    weekly)
      day=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
        --ok-button "Next" --cancel-button "Back" \
        --radiolist "Which day of the week?" 18 60 7 \
        1 Monday ON 2 Tuesday OFF 3 Wednesday OFF 4 Thursday OFF \
        5 Friday OFF 6 Saturday OFF 0 Sunday OFF 3>&1 1>&2 2>&3) || return 2
      ask_time "03:00" || return 2
      case "$day" in
        0) dname=Sunday;; 1) dname=Monday;; 2) dname=Tuesday;; 3) dname=Wednesday;;
        4) dname=Thursday;; 5) dname=Friday;; 6) dname=Saturday;;
      esac
      CRON_EXPR="$TIME_M $TIME_H * * $day"
      SCHED_DESC="Every $dname at $(hhmm "$TIME_H" "$TIME_M")" ;;
    monthly)
      while true; do
        day=$(ask_input "Which day of the month? (1-28)" "1") || return 2
        if [[ "$day" =~ ^[0-9]+$ ]] && (( 10#$day >= 1 && 10#$day <= 28 )); then
          day=$((10#$day)); break
        fi
        msg "Enter a number between 1 and 28 (so it works in every month)."
      done
      ask_time "03:00" || return 2
      CRON_EXPR="$TIME_M $TIME_H $day * *"
      SCHED_DESC="Day $day of every month at $(hhmm "$TIME_H" "$TIME_M")" ;;
    custom)
      while true; do
        day=$(ask_input "Enter a cron expression (5 fields):\n  minute hour day-of-month month day-of-week\n\nExample: 30 2 * * 0   (Sundays at 02:30)" "${CRON_EXPR:-0 3 * * *}") || return 2
        day=$(echo "$day" | xargs)
        if [[ "$day" =~ ^[A-Za-z0-9*/,-]+(\ +[A-Za-z0-9*/,-]+){4}$ ]]; then
          break
        fi
        msg "That is not a valid 5-field cron expression."
      done
      CRON_EXPR="$day"
      SCHED_DESC="Custom cron: $day" ;;
  esac
  SCHED_KEY="$key"
  return 0
}

step_retention() {
  local v
  v=$(ask_input "How many of the most recent backups should be kept PER VM / CT?\n(1 - 365)" "$KEEP") || return 1
  if ! [[ "$v" =~ ^[0-9]+$ ]] || (( 10#$v < 1 || 10#$v > 365 )); then
    msg "Enter a number between 1 and 365."
    return 2
  fi
  KEEP=$((10#$v))
  return 0
}

step_order() {
  local v
  v=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "What should happen when the limit ($KEEP) is reached?" 16 78 2 \
    backup_first "Take the new backup first, THEN delete the old ones (safer)" "$(oo "$ORDER" backup_first)" \
    delete_first "Delete the oldest first, THEN take the new backup (saves space)" "$(oo "$ORDER" delete_first)" \
    3>&1 1>&2 2>&3) || return 1
  ORDER="$v"
  if [[ "$ORDER" == "delete_first" ]]; then
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox \
"Heads up: with 'delete first' the oldest backup is removed BEFORE the new one is made.\n\nIf the new backup fails you will temporarily have only $((KEEP-1)) backup(s).\n\nUse it only when disk space is tight." 14 74
  fi
  return 0
}

step_options() {
  local m c
  m=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "Backup mode:" 15 78 3 \
    snapshot "Snapshot - VM keeps running (recommended)" "$(oo "$MODE" snapshot)" \
    suspend  "Suspend  - short pause, then resume"        "$(oo "$MODE" suspend)" \
    stop     "Stop     - shut down, back up, start again"  "$(oo "$MODE" stop)" \
    3>&1 1>&2 2>&3) || return 1
  c=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "Compression:" 16 78 4 \
    zstd "zstd - fast and efficient (recommended)" "$(oo "$COMPRESS" zstd)" \
    gzip "gzip - compatible, slower"               "$(oo "$COMPRESS" gzip)" \
    lzo  "lzo  - very fast, larger files"          "$(oo "$COMPRESS" lzo)" \
    0    "none - no compression"                   "$(oo "$COMPRESS" 0)" \
    3>&1 1>&2 2>&3) || return 2
  MODE="$m"; COMPRESS="$c"
  return 0
}

step_dest() {
  local v
  v=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "Where should the backups be stored?\n\nRemote targets are processed one VM at a time: back up -> upload -> verify -> free the local space -> next VM." \
    24 80 9 \
    local_storage "Proxmox storage (local disk, LVM-thin dir, USB, NFS, CIFS...)" "$(oo "$DEST_KIND" local_storage)" \
    local_dir     "Custom local directory (e.g. a mounted external disk)"          "$(oo "$DEST_KIND" local_dir)" \
    ftp           "FTP / FTPS server"                                              "$(oo "$DEST_KIND" ftp)" \
    sftp          "SFTP (SSH) server or NAS"                                       "$(oo "$DEST_KIND" sftp)" \
    cloud         "Cloud drive: Google Drive, OneDrive, Dropbox, Mega, ..."        "$(oo "$DEST_KIND" cloud)" \
    s3            "S3-compatible: AWS, Wasabi, MinIO, Cloudflare R2, ..."          "$(oo "$DEST_KIND" s3)" \
    b2            "Backblaze B2"                                                   "$(oo "$DEST_KIND" b2)" \
    webdav        "WebDAV: Nextcloud, ownCloud, ..."                               "$(oo "$DEST_KIND" webdav)" \
    3>&1 1>&2 2>&3) || return 1
  DEST_KIND="$v"
  case "$v" in
    local_storage) DEST_TYPE=storage ;;
    local_dir)     DEST_TYPE=dir ;;
    *)             DEST_TYPE=remote ;;
  esac
  return 0
}

ensure_rclone() {
  command -v rclone >/dev/null 2>&1 && return 0
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --yes-button "Install" --no-button "Back" \
    --yesno "rclone is required for this destination but is not installed.\n\nInstall it now?" 12 70 || return 1
  clear
  if ! { apt-get update -qq && apt-get install -y rclone; }; then
    curl -fsSL https://rclone.org/install.sh | bash
  fi
  command -v rclone >/dev/null 2>&1 || { msg "rclone installation failed. Install it manually and run the installer again."; return 1; }
  return 0
}

rc_create() {
  local type="$1" err; shift
  rclone config delete "$RC_NAME" >/dev/null 2>&1
  if ! err=$(rclone config create "$RC_NAME" "$type" "$@" --obscure 2>&1); then
    msg "Could not create the rclone remote:\n\n$err"
    return 1
  fi
  return 0
}

finalize_remote() {
  local name="$1" p s err
  p=$(ask_input "$2" "${REMOTE_PATH:-$3}") || return 2
  s=$(ask_input "Temporary local staging folder.\nIt must have free space for your LARGEST single VM backup." "${STAGING:-/var/tmp/pve-backup-staging}") || return 2
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --infobox "Testing the connection to ${name}:${p} ..." 6 70
  if ! err=$(timeout 120 rclone mkdir "${name}:${p}" 2>&1); then
    msg "Connection test FAILED:\n\n$(echo "$err" | tail -n 6)"
    return 2
  fi
  REMOTE_NAME="$name"; REMOTE_PATH="$p"; STAGING="$s"
  mkdir -p "$STAGING" 2>/dev/null
  msg "Connection OK.\n\nRemote : ${REMOTE_NAME}:${REMOTE_PATH}\nStaging: ${STAGING}"
  return 0
}

detail_storage() {
  local items=() name type status avail out st
  while read -r name type status avail; do
    [[ -n "$name" ]] || continue
    st=OFF; [[ "$STORAGE" == "$name" ]] && st=ON
    items+=("$name" "${type}, ${status}, free $(( ${avail:-0} / 1048576 )) GB" "$st")
  done < <(pvesm status --content backup 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $6}')

  if [[ ${#items[@]} -eq 0 ]]; then
    msg "No storage with 'backup' content type was found.\n\nAdd one in Datacenter -> Storage (enable 'VZDump backup file'), or use the 'Custom local directory' option."
    return 1
  fi
  out=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "Choose the Proxmox storage (disk) for the backups:" 20 78 10 \
    "${items[@]}" 3>&1 1>&2 2>&3) || return 1
  STORAGE="$out"
  return 0
}

detail_dir() {
  local p
  p=$(ask_input "Full path of the backup directory.\nExample: /mnt/usb-backup" "${DIR:-/mnt/backup}") || return 1
  if [[ "$p" != /* ]]; then msg "Please enter an absolute path (starting with /)."; return 2; fi
  if [[ ! -d "$p" ]]; then
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --yesno "$p does not exist. Create it?" 8 60 || return 2
    mkdir -p "$p" || { msg "Could not create $p"; return 2; }
  fi
  if ! touch "$p/.pve-backup-test" 2>/dev/null; then
    msg "$p is not writable."
    return 2
  fi
  rm -f "$p/.pve-backup-test"
  DIR="$p"
  return 0
}

detail_ftp() {
  local h p u pw args=()
  h=$(ask_input "FTP server host name or IP:" "") || return 1
  p=$(ask_input "Port:" "21") || return 2
  u=$(ask_input "Username:" "") || return 2
  pw=$(ask_pass "Password:") || return 2
  args=(host="$h" port="$p" user="$u" pass="$pw")
  if whiptail --title "$TITLE" --backtitle "$BACKTITLE" --defaultno \
       --yesno "Use FTPS (explicit TLS encryption)?\n\nStrongly recommended if the server supports it." 10 66; then
    args+=(explicit_tls=true)
  fi
  ensure_rclone || return 1
  rc_create ftp "${args[@]}" || return 2
  finalize_remote "$RC_NAME" "Folder on the FTP server for backups (created if missing):" "proxmox-backups/$(hostname)"
}

detail_sftp() {
  local h p u auth pw args=()
  h=$(ask_input "SFTP server host name or IP:" "") || return 1
  p=$(ask_input "SSH port:" "22") || return 2
  u=$(ask_input "Username:" "") || return 2
  auth=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "Authentication method:" 12 70 2 \
    password "Password" ON \
    key      "SSH key (recommended)" OFF 3>&1 1>&2 2>&3) || return 2
  args=(host="$h" port="$p" user="$u")
  ensure_rclone || return 1
  if [[ "$auth" == "password" ]]; then
    pw=$(ask_pass "Password:") || return 2
    args+=(pass="$pw")
  else
    [[ -f /root/.ssh/id_ed25519 ]] || { mkdir -p /root/.ssh; ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_ed25519; }
    msg "Add this PUBLIC key to ~/.ssh/authorized_keys of '$u' on the server, then press OK:\n\n$(cat /root/.ssh/id_ed25519.pub)"
    args+=(key_file=/root/.ssh/id_ed25519)
  fi
  rc_create sftp "${args[@]}" || return 2
  finalize_remote "$RC_NAME" "Folder on the SFTP server for backups (created if missing):" "proxmox-backups/$(hostname)"
}

detail_webdav() {
  local url vendor u pw
  url=$(ask_input "WebDAV URL.\nNextcloud example: https://cloud.example.com/remote.php/dav/files/USERNAME/" "") || return 1
  vendor=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "WebDAV vendor:" 14 66 3 \
    nextcloud "Nextcloud" ON owncloud "ownCloud" OFF other "Other" OFF 3>&1 1>&2 2>&3) || return 2
  u=$(ask_input "Username:" "") || return 2
  pw=$(ask_pass "Password (use an app password for Nextcloud):") || return 2
  ensure_rclone || return 1
  rc_create webdav url="$url" vendor="$vendor" user="$u" pass="$pw" || return 2
  finalize_remote "$RC_NAME" "Folder for backups (created if missing):" "proxmox-backups/$(hostname)"
}

detail_s3() {
  local prov ak sk ep reg args=()
  prov=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --ok-button "Next" --cancel-button "Back" \
    --radiolist "S3 provider:" 18 74 6 \
    AWS          "Amazon S3" ON \
    Wasabi       "Wasabi" OFF \
    Minio        "MinIO (self-hosted)" OFF \
    Cloudflare   "Cloudflare R2" OFF \
    DigitalOcean "DigitalOcean Spaces" OFF \
    Other        "Other S3-compatible (Hetzner, Backblaze S3, ...)" OFF 3>&1 1>&2 2>&3) || return 1
  ak=$(ask_input "Access key ID:" "") || return 2
  sk=$(ask_pass "Secret access key:") || return 2
  ep=$(ask_input "Endpoint URL (leave empty for AWS):" "") || return 2
  reg=$(ask_input "Region, e.g. us-east-1 (leave empty if not needed):" "") || return 2
  args=(provider="$prov" access_key_id="$ak" secret_access_key="$sk")
  [[ -n "$ep"  ]] && args+=(endpoint="$ep")
  [[ -n "$reg" ]] && args+=(region="$reg")
  ensure_rclone || return 1
  rc_create s3 "${args[@]}" || return 2
  finalize_remote "$RC_NAME" "Bucket and folder (format: bucket/folder):" "my-bucket/proxmox-backups/$(hostname)"
}

detail_b2() {
  local acc key
  acc=$(ask_input "Backblaze B2 Application Key ID (or account ID):" "") || return 1
  key=$(ask_pass "Application Key:") || return 2
  ensure_rclone || return 1
  rc_create b2 account="$acc" key="$key" || return 2
  finalize_remote "$RC_NAME" "Bucket and folder (format: bucket/folder):" "my-bucket/proxmox-backups/$(hostname)"
}

detail_cloud() {
  local rems=() items=() r out
  ensure_rclone || return 1
  while true; do
    mapfile -t rems < <(rclone listremotes 2>/dev/null | sed 's/:$//')
    items=()
    for r in "${rems[@]}"; do
      [[ -n "$r" ]] && items+=("$r" "existing rclone remote" "$(oo "$REMOTE_NAME" "$r")")
    done
    items+=("__new__" "Create a NEW remote now (runs 'rclone config')" "OFF")

    out=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
      --ok-button "Next" --cancel-button "Back" \
      --radiolist "Choose the cloud remote (Google Drive, OneDrive, Dropbox, Mega, ...)" 20 78 10 \
      "${items[@]}" 3>&1 1>&2 2>&3) || return 1

    if [[ "$out" == "__new__" ]]; then
      clear
      cat <<'EOT'
=== rclone config ===
Create a remote with:   n) New remote
Pick your provider (e.g. drive = Google Drive, onedrive, dropbox, mega ...)

On a HEADLESS server, when asked
  "Use web browser to automatically authenticate rclone with remote?"
answer  n  and then run the command it shows on a PC with a browser:
  rclone authorize "drive"
Paste the resulting token back here.

When finished choose  q) Quit config
EOT
      echo
      rclone config
      continue
    fi
    break
  done
  finalize_remote "$out" "Folder on the remote for backups (created if missing):" "proxmox-backups/$(hostname)"
}

step_dest_detail() {
  case "$DEST_KIND" in
    local_storage) detail_storage ;;
    local_dir)     detail_dir ;;
    ftp)           detail_ftp ;;
    sftp)          detail_sftp ;;
    cloud)         detail_cloud ;;
    s3)            detail_s3 ;;
    b2)            detail_b2 ;;
    webdav)        detail_webdav ;;
  esac
}

dest_desc() {
  case "$DEST_TYPE" in
    storage) echo "Proxmox storage '${STORAGE}'" ;;
    dir)     echo "Directory ${DIR}" ;;
    remote)  echo "${REMOTE_NAME}:${REMOTE_PATH}  (staging: ${STAGING})" ;;
  esac
}

step_summary() {
  local names="" id order_txt
  for id in $VMIDS; do names+="  - ${id}  ${VMNAME[$id]:-?}\n"; done
  if [[ "$ORDER" == "backup_first" ]]; then
    order_txt="backup first, then delete old"
  else
    order_txt="delete oldest first, then backup"
  fi
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" \
    --yes-button "Install" --no-button "Back" \
    --yesno "Please review your settings:\n\nVMs / CTs:\n${names}\nSchedule    : ${SCHED_DESC}\nCron        : ${CRON_EXPR}\nKeep last   : ${KEEP} backup(s) per VM/CT\nOrder       : ${order_txt}\nMode / comp.: ${MODE} / ${COMPRESS}\nDestination : $(dest_desc)\n\nSelect <Install> to write the config and add the cron job." \
    28 80 || return 1
  return 0
}

run_wizard() {
  local steps=(step_vms step_schedule step_retention step_order step_options step_dest step_dest_detail step_summary)
  local i=0 rc total=${#steps[@]}
  while (( i < total )); do
    BACKTITLE="PVE Backup Manager - by Eren Akkuş   |   Step $((i+1)) / ${total}"
    "${steps[$i]}"; rc=$?
    case $rc in
      0) i=$((i+1)) ;;
      2) : ;;
      *) if (( i == 0 )); then
           if whiptail --title "$TITLE" --yesno "Exit the installer?" 8 50; then return 1; fi
         else
           i=$((i-1))
         fi ;;
    esac
  done
  BACKTITLE="PVE Backup Manager - by Eren Akkuş"
  return 0
}

write_runner() {
  cat > "$RUNNER" <<'RUNNER_EOF'
set -o pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CONF="/etc/pve-backup-manager/pve-backup-manager.conf"
[[ -r "$CONF" ]] || { echo "Config not found: $CONF"; exit 2; }
source "$CONF"
: "${STORAGE:=}" "${DIR:=}" "${REMOTE_NAME:=}" "${REMOTE_PATH:=}" "${STAGING:=/var/tmp/pve-backup-staging}"

exec 9>/var/lock/pve-backup-manager.lock
if ! flock -n 9; then
  echo "[$(date '+%F %T')] Another backup run is still active - exiting."
  exit 1
fi

log() { echo "[$(date '+%F %T')] $*"; }
vm_exists() { [[ -f "/etc/pve/qemu-server/$1.conf" || -f "/etc/pve/lxc/$1.conf" ]]; }
strip_ext() { sed -E 's/\.(vma|tar)(\.(zst|gz|lzo))?$//'; }

VZ_ARGS=(--mode "$MODE" --compress "$COMPRESS" --quiet 1)

prune_storage() {
  local id=$1 keep=$2 vols=() n i
  mapfile -t vols < <(pvesm list "$STORAGE" --vmid "$id" --content backup 2>/dev/null | awk 'NR>1 {print $1}' | sort)
  n=$(( ${#vols[@]} - keep ))
  for (( i=0; i<n; i++ )); do
    log "  Deleting old backup: ${vols[$i]}"
    pvesm free "${vols[$i]}" >/dev/null 2>&1 || log "  WARNING: could not delete ${vols[$i]}"
  done
}

prune_dir() {
  local id=$1 keep=$2 files=() n i base
  mapfile -t files < <(find "$DIR" -maxdepth 1 -type f -regextype posix-extended \
    -regex ".*/vzdump-(qemu|lxc)-${id}-[0-9_-]+\.(vma|tar)(\.(zst|gz|lzo))?$" | sort)
  n=$(( ${#files[@]} - keep ))
  for (( i=0; i<n; i++ )); do
    log "  Deleting old backup: ${files[$i]}"
    base=$(echo "${files[$i]}" | strip_ext)
    rm -f -- "$base".*
  done
}

prune_remote() {
  local id=$1 keep=$2 R="${REMOTE_NAME}:${REMOTE_PATH}" files=() n i base
  mapfile -t files < <(rclone lsf "$R" --files-only 2>/dev/null \
    | grep -E "^vzdump-(qemu|lxc)-${id}-[0-9_-]+\.(vma|tar)(\.(zst|gz|lzo))?$" | sort)
  n=$(( ${#files[@]} - keep ))
  for (( i=0; i<n; i++ )); do
    log "  Deleting old remote backup: ${files[$i]}"
    base=$(echo "${files[$i]}" | strip_ext)
    rclone delete "$R" --include "${base}.*" >/dev/null 2>&1 || log "  WARNING: could not delete ${files[$i]}"
  done
}

prune() {
  case "$DEST_TYPE" in
    storage) prune_storage "$@" ;;
    dir)     prune_dir "$@" ;;
    remote)  prune_remote "$@" ;;
  esac
}

backup_remote() {
  local id=$1 R="${REMOTE_NAME}:${REMOTE_PATH}"
  mkdir -p "$STAGING" || return 1
  find "$STAGING" -maxdepth 1 -name "vzdump-*-${id}-*" -delete
  if ! vzdump "$id" "${VZ_ARGS[@]}" --dumpdir "$STAGING"; then
    find "$STAGING" -maxdepth 1 -name "vzdump-*-${id}-*" -delete
    return 1
  fi
  log "  Uploading to $R ..."
  if rclone copy "$STAGING" "$R" --include "vzdump-*-${id}-*" --transfers 1 --retries 3 \
     && rclone check "$STAGING" "$R" --include "vzdump-*-${id}-*" --one-way --size-only >/dev/null 2>&1; then
    find "$STAGING" -maxdepth 1 -name "vzdump-*-${id}-*" -delete
    return 0
  fi
  log "  ERROR: upload/verification failed. Local copy kept in $STAGING"
  return 1
}

do_backup() {
  local id=$1
  case "$DEST_TYPE" in
    storage) vzdump "$id" "${VZ_ARGS[@]}" --storage "$STORAGE" ;;
    dir)     vzdump "$id" "${VZ_ARGS[@]}" --dumpdir "$DIR" ;;
    remote)  backup_remote "$id" ;;
  esac
}

ok=0; fail=0; skipped=0
log "===== Backup run started | keep=$KEEP order=$ORDER dest=$DEST_TYPE ====="

for id in $VMIDS; do
  if ! vm_exists "$id"; then
    log "VMID $id not found on this node - skipping."
    skipped=$((skipped+1)); continue
  fi
  log "--- VMID $id ---"
  if [[ "$ORDER" == "delete_first" ]]; then
    prune "$id" $(( KEEP - 1 ))
  fi
  if do_backup "$id"; then
    log "  Backup OK"
    if [[ "$ORDER" == "backup_first" ]]; then prune "$id" "$KEEP"; fi
    ok=$((ok+1))
  else
    log "  Backup FAILED"
    fail=$((fail+1))
  fi
done

log "===== Finished: ok=$ok failed=$fail skipped=$skipped ====="
[[ $fail -eq 0 ]]
RUNNER_EOF
  chmod 755 "$RUNNER"
}

write_config() {
  mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
  {
    echo "# Generated by PVE Backup Manager v${VERSION} (Eren Akkuş) on $(date '+%F %T')"
    printf 'VMIDS=%q\n'        "$VMIDS"
    printf 'SCHED_KEY=%q\n'    "$SCHED_KEY"
    printf 'SCHED_DESC=%q\n'   "$SCHED_DESC"
    printf 'CRON_EXPR=%q\n'    "$CRON_EXPR"
    printf 'KEEP=%q\n'         "$KEEP"
    printf 'ORDER=%q\n'        "$ORDER"
    printf 'MODE=%q\n'         "$MODE"
    printf 'COMPRESS=%q\n'     "$COMPRESS"
    printf 'DEST_KIND=%q\n'    "$DEST_KIND"
    printf 'DEST_TYPE=%q\n'    "$DEST_TYPE"
    printf 'STORAGE=%q\n'      "$STORAGE"
    printf 'DIR=%q\n'          "$DIR"
    printf 'REMOTE_NAME=%q\n'  "$REMOTE_NAME"
    printf 'REMOTE_PATH=%q\n'  "$REMOTE_PATH"
    printf 'STAGING=%q\n'      "$STAGING"
  } > "$CONF_FILE"
  chmod 600 "$CONF_FILE"
}

write_cron() {
  cat > "$CRON_FILE" <<EOF
# Managed by ${APP} (Eren Akkuş) - re-run the installer to change this schedule.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${CRON_EXPR} root ${RUNNER} >> ${LOG_FILE} 2>&1
EOF
  chmod 644 "$CRON_FILE"
}

write_logrotate() {
  cat > "$LOGROTATE_FILE" <<EOF
${LOG_FILE} {
    monthly
    rotate 6
    compress
    missingok
    notifempty
}
EOF
}

do_install() {
  write_config
  write_runner
  write_cron
  write_logrotate
  touch "$LOG_FILE"; chmod 640 "$LOG_FILE"

  msg "Installation complete!\n\nSchedule : ${SCHED_DESC}\nCron file: ${CRON_FILE}\nRunner   : ${RUNNER}\nConfig   : ${CONF_FILE}\nLog file : ${LOG_FILE}"

  if whiptail --title "$TITLE" --backtitle "$BACKTITLE" --defaultno \
       --yesno "Run the first backup now?\n\n(You can also run it any time with: pve-backup-run)" 11 66; then
    run_now
  fi
}

run_now() {
  [[ -x "$RUNNER" ]] || { msg "Not installed yet. Please install first."; return; }
  clear
  echo "Running backup now - output is also appended to ${LOG_FILE}"
  echo
  "$RUNNER" 2>&1 | tee -a "$LOG_FILE"
  echo
  read -r -p "Press ENTER to return to the menu..." _
}

do_uninstall() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --defaultno \
    --yesno "Remove the cron job and the runner?\n\nExisting backup files are NOT deleted." 10 66 || return
  rm -f "$CRON_FILE" "$RUNNER" "$LOGROTATE_FILE"
  if whiptail --title "$TITLE" --backtitle "$BACKTITLE" --defaultno \
       --yesno "Also delete the configuration in ${CONF_DIR}?" 8 66; then
    rm -rf "$CONF_DIR"
  fi
  msg "PVE Backup Manager has been uninstalled.\n\n(rclone remote '${RC_NAME}' and the rclone package were left untouched.)"
}

main_menu() {
  local c state
  while true; do
    state="NOT installed"; [[ -f "$CRON_FILE" ]] && state="installed"
    c=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" --cancel-button "Exit" \
      --menu "Status: ${state}\n\nWhat would you like to do?" 20 74 7 \
      install   "Install / reconfigure scheduled backups" \
      run       "Run a backup now" \
      status    "Show current configuration" \
      log       "View the backup log" \
      uninstall "Uninstall (cron job + runner)" \
      exit      "Exit" 3>&1 1>&2 2>&3) || break
    case "$c" in
      install)
        load_existing
        if run_wizard; then do_install; fi ;;
      run) run_now ;;
      status)
        if [[ -f "$CONF_FILE" ]]; then
          whiptail --title "$TITLE" --backtitle "$BACKTITLE" --textbox "$CONF_FILE" 24 78
        else
          msg "Nothing is installed yet."
        fi ;;
      log)
        if [[ -s "$LOG_FILE" ]]; then
          whiptail --title "$TITLE" --backtitle "$BACKTITLE" --scrolltext --textbox "$LOG_FILE" 30 100
        else
          msg "The log is empty."
        fi ;;
      uninstall) do_uninstall ;;
      exit) break ;;
    esac
  done
  clear
}

need_root
case "${1:-}" in
  --run)       [[ -x "$RUNNER" ]] || die "Not installed. Run the installer first."; exec "$RUNNER" ;;
  --uninstall) check_env; do_uninstall; clear; exit 0 ;;
  -h|--help)
    echo "PVE Backup Manager v${VERSION} - by Eren Akkuş"
    echo "Usage: sudo $0 [--run | --uninstall | --help]"
    exit 0 ;;
esac
check_env
main_menu
