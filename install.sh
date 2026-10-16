#!/bin/bash
# Instala CSB en el host Proxmox. Licencia GPLv2.
#   ./install.sh          copia backup y backup-prune a /usr/local/bin
#   ./install.sh --cron   además instala /etc/cron.d/csb (diario 03:00)
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "Ejecútalo como root." >&2; exit 1; }
command -v pct > /dev/null || { echo "No encuentro 'pct': esto debe ejecutarse en el host Proxmox." >&2; exit 1; }
cd "$(dirname "$0")"
install -m 755 backup /usr/local/bin/backup
install -m 755 backup-prune /usr/local/bin/backup-prune
echo "Instalados: /usr/local/bin/backup y /usr/local/bin/backup-prune"
command -v dialog > /dev/null || echo "Aviso: falta 'dialog' (solo necesario para los menús): apt install dialog"
if [ "${1:-}" = "--cron" ]; then
    if [ -e /etc/cron.d/csb ]; then
        cp -a /etc/cron.d/csb "/etc/cron.d/csb.bak.$(date +%F_%H%M%S)"
        echo "Había un /etc/cron.d/csb: se guardó una copia .bak"
    fi
    install -m 644 etc/cron.d/csb /etc/cron.d/csb
    echo "Cron instalado: /etc/cron.d/csb"
else
    echo "Cron NO instalado. Revisa el README y usa ./install.sh --cron cuando hayas probado una copia."
fi
