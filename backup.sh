#!/bin/bash
# CREALIB RECOVERY FORMAT Ver. 1.0
# Autor: Charlie Martínez <cmartinez@crealib.net>
# Licencia: GPLv2 https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
# Herramienta genérica para revisión, recuperación y formateo de HDD de reciclaje

# ---------- DETECCIÓN DE IDIOMA ----------

SYS_LANG="${LANG:-$LC_ALL}"

if [[ "$SYS_LANG" == es* || "$SYS_LANG" == ES* ]]; then
  LANGMODE="ES"
else
  LANGMODE="EN"
fi

if [[ "$LANGMODE" == "ES" ]]; then
  MSG_DEP_TITLE="Dependencia requerida"
  MSG_DEP_TEXT="Se requiere instalar la dependencia:\n\n  dialog\n\n¿Deseas instalarla ahora?"
  MSG_NO_DEP="No se puede ejecutar el programa sin la dependencia dialog."
  MSG_NO_NET="No hay conexión a internet.\nNo se puede instalar la dependencia requerida."
  MSG_NO_USB="No se detectaron discos HDD conectados por USB."
  MSG_MENU_TITLE="CREALIB FORMAT"
  MSG_MENU_TEXT="Seleccione el HDD USB:"
  MSG_CONFIRM_ZERO="¿CONFIRMAS el BORRADO TOTAL de:\n\n%s\n\nESTA ACCIÓN ES IRREVERSIBLE?"
  MSG_WORKING="Formateando..."
  MSG_DONE="BORRADO COMPLETO FINALIZADO:\n\n%s"
  MSG_SMART_BEFORE="Estado SMART ANTES del proceso:"
  MSG_SMART_AFTER="Estado SMART DESPUÉS del proceso:"
  MSG_BADBLOCKS="¿Deseas intentar RECUPERACIÓN DE SECTORES (badblocks)?\n\nProceso lento pero más efectivo."
  MSG_DISK_GOOD="RESULTADO FINAL:\n\nDISCO APTO PARA USO"
  MSG_DISK_BAD="RESULTADO FINAL:\n\nDISCO NO APTO PARA USO\n(SECTORES DEFECTUOSOS ACTIVOS)"
else
  MSG_DEP_TITLE="Required dependency"
  MSG_DEP_TEXT="The following dependency is required:\n\n  dialog\n\nDo you want to install it now?"
  MSG_NO_DEP="The program cannot run without the dialog dependency."
  MSG_NO_NET="No internet connection.\nCannot install required dependency."
  MSG_NO_USB="No USB connected HDD detected."
  MSG_MENU_TITLE="CREALIB FORMAT"
  MSG_MENU_TEXT="Select the USB HDD:"
  MSG_CONFIRM_ZERO="DO YOU CONFIRM TOTAL ERASE OF:\n\n%s\n\nTHIS ACTION IS IRREVERSIBLE?"
  MSG_WORKING="Formatting..."
  MSG_DONE="FULL ERASE COMPLETED:\n\n%s"
  MSG_SMART_BEFORE="SMART status BEFORE process:"
  MSG_SMART_AFTER="SMART status AFTER process:"
  MSG_BADBLOCKS="Do you want to attempt SECTOR RECOVERY (badblocks)?\n\nSlow but more effective."
  MSG_DISK_GOOD="FINAL RESULT:\n\nDISK SUITABLE FOR USE"
  MSG_DISK_BAD="FINAL RESULT:\n\nDISK NOT SUITABLE\n(DEFECTIVE SECTORS ACTIVE)"
fi

MSG_BACK_TITLE="CREALIB RECOVERY FORMAT (CRF) v1.1 - By Charlie Martinez®, GPLv2"

# ---------- FUNCIONES ----------

check_internet() {
  ping -c 1 -W 2 8.8.8.8 &>/dev/null
}

install_dialog() {
  if command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y dialog smartmontools e2fsprogs
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y dialog smartmontools e2fsprogs
  elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm dialog smartmontools e2fsprogs
  elif command -v zypper &>/dev/null; then
    sudo zypper install -y dialog smartmontools e2fsprogs
  else
    echo "ERROR: Package manager not supported."
    exit 1
  fi
}

get_smart_summary() {
  sudo smartctl -A "$1" | awk '
  /Reallocated_Sector_Ct/ {r=$10}
  /Current_Pending_Sector/ {p=$10}
  /Offline_Uncorrectable/ {u=$10}
  END {printf "Reallocated: %s\nPending: %s\nUncorrectable: %s\n", r, p, u}'
}

disk_health_check() {
  local P U
  P=$(sudo smartctl -A "$1" | awk '/Current_Pending_Sector/ {print $10}')
  U=$(sudo smartctl -A "$1" | awk '/Offline_Uncorrectable/ {print $10}')
  [[ "$P" == "0" && "$U" == "0" ]]
}

# ---------- VERIFICACIÓN DE DIALOG ----------

if ! command -v dialog &>/dev/null; then
  if ! check_internet; then
    echo -e "$MSG_NO_NET"
    exit 1
  fi

  dialog --title "$MSG_DEP_TITLE" \
         --backtitle "$MSG_BACK_TITLE" \
         --yesno "$MSG_DEP_TEXT" 10 55

  RESP=$? ; clear
  [[ $RESP -ne 0 ]] && exit 1
  install_dialog
fi

# ---------- DETECCIÓN HDD USB REALES ----------

mapfile -t DISKS < <(
  lsblk -ndo NAME,TRAN,TYPE,SIZE | \
  awk '$2=="usb" && $3=="disk" && $4 != "0B" {print "/dev/"$1" "$4}'
)

[[ ${#DISKS[@]} -eq 0 ]] && {
  dialog --backtitle "$MSG_BACK_TITLE" --msgbox "$MSG_NO_USB" 7 60
  clear ; exit 1
}

MENU_ITEMS=()
for DISK in "${DISKS[@]}"; do
  DEV=$(echo "$DISK" | awk '{print $1}')
  SIZE=$(echo "$DISK" | awk '{print $2}')
  MODEL=$(udevadm info --query=property --name="$DEV" | grep '^ID_MODEL=' | cut -d= -f2)
  MENU_ITEMS+=("$DEV" "$SIZE${MODEL:+ — $MODEL}")
done

DISK_SELECTED=$(dialog --backtitle "$MSG_BACK_TITLE" \
  --title "$MSG_MENU_TITLE" \
  --menu "$MSG_MENU_TEXT" 16 70 8 \
  "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)

clear
[[ -z "$DISK_SELECTED" ]] && exit 0

# ---------- SMART ANTES ----------

SMART_BEFORE=$(get_smart_summary "$DISK_SELECTED")
dialog --backtitle "$MSG_BACK_TITLE" \
       --msgbox "$MSG_SMART_BEFORE\n\n$SMART_BEFORE" 12 60

# ---------- RECUPERACIÓN BADBLOCKS ----------

dialog --backtitle "$MSG_BACK_TITLE" --yesno "$MSG_BADBLOCKS" 10 60
if [[ $? -eq 0 ]]; then
  (
    sudo badblocks -wsv "$DISK_SELECTED"
  ) | dialog --backtitle "$MSG_BACK_TITLE" \
             --title "badblocks" --programbox 16 85
fi

# ---------- CONFIRMACIÓN BORRADO ----------

CONFIRM_MSG=$(printf "$MSG_CONFIRM_ZERO" "$DISK_SELECTED")
dialog --backtitle "$MSG_BACK_TITLE" --yesno "$CONFIRM_MSG" 12 70
[[ $? -ne 0 ]] && exit 0

(
  sudo dd if=/dev/zero of="$DISK_SELECTED" bs=4M status=progress conv=fsync
) | dialog --backtitle "$MSG_BACK_TITLE" \
           --title "$MSG_WORKING" --programbox 16 85

sync

# ---------- SMART DESPUÉS ----------

SMART_AFTER=$(get_smart_summary "$DISK_SELECTED")
dialog --backtitle "$MSG_BACK_TITLE" \
       --msgbox "$MSG_SMART_AFTER\n\n$SMART_AFTER" 12 60

# ---------- VEREDICTO FINAL ----------

if disk_health_check "$DISK_SELECTED"; then
  dialog --backtitle "$MSG_BACK_TITLE" --msgbox "$MSG_DISK_GOOD" 8 50
else
  dialog --backtitle "$MSG_BACK_TITLE" --msgbox "$MSG_DISK_BAD" 8 60
fi

clear
