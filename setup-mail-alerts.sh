#!/bin/bash
# setup-mail-alerts.sh - Configura postfix del host Proxmox para enviar las alertas de cron
# a través de un SMTP externo (SMTPS, puerto 465) y reenviar el correo de root a tu dirección.
# Licencia GPLv2.
#
# Los valores de abajo son FICTICIOS. Cámbialos por los tuyos, bien editando este fichero
# o bien pasándolos como variables de entorno:
#
#   SMTP_HOST=smtp.example.com SMTP_USER=alertas@example.com ALERT_TO=admin@example.org ./setup-mail-alerts.sh
#
# La contraseña NO se guarda en este fichero: se pide por teclado.

set -euo pipefail

SMTP_HOST="${SMTP_HOST:-smtp.example.com}"        # Servidor SMTP
SMTP_PORT="${SMTP_PORT:-465}"                     # 465 = SMTPS (TLS directo)
SMTP_USER="${SMTP_USER:-alertas@example.com}"     # Cuenta con la que se envía (será también el remitente)
ALERT_TO="${ALERT_TO:-admin@example.org}"         # Dónde quieres recibir los avisos

[ "$EUID" -eq 0 ] || { echo "Ejecútalo como root." >&2; exit 1; }

if [ "$SMTP_HOST" = "smtp.example.com" ]; then
    echo "Estás usando los valores de ejemplo (smtp.example.com). Edita el script o pasa las variables de entorno." >&2
    exit 1
fi

read -rsp "Contraseña SMTP de $SMTP_USER: " SMTP_PASS
echo

apt-get install -y postfix libsasl2-modules mailutils

cp -a /etc/postfix/main.cf "/etc/postfix/main.cf.bak.$(date +%F_%H%M%S)"

# Credenciales (solo legibles por root)
umask 077
printf '[%s]:%s %s:%s\n' "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USER" "$SMTP_PASS" > /etc/postfix/sasl_passwd
unset SMTP_PASS
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

# Muchos SMTP exigen que el remitente sea la cuenta autenticada: se reescribe el remitente de root.
HOSTNAME_FQDN="$(postconf -h myhostname)"
echo "root@${HOSTNAME_FQDN} ${SMTP_USER}" > /etc/postfix/sender_canonical
postmap /etc/postfix/sender_canonical

postconf -e "relayhost = [${SMTP_HOST}]:${SMTP_PORT}"
postconf -e 'smtp_sasl_auth_enable = yes'
postconf -e 'smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd'
postconf -e 'smtp_sasl_security_options = noanonymous'
postconf -e 'smtp_tls_wrappermode = yes'
postconf -e 'smtp_tls_security_level = encrypt'
postconf -e 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt'
postconf -e 'sender_canonical_maps = hash:/etc/postfix/sender_canonical'

# Reenviar el correo de root a tu dirección
if grep -q '^root:' /etc/aliases; then
    sed -i "s/^root:.*/root: ${ALERT_TO}/" /etc/aliases
else
    echo "root: ${ALERT_TO}" >> /etc/aliases
fi
newaliases
systemctl restart postfix

cat <<EOF

Listo. Prueba el envío con:

  printf 'Subject: Prueba de alertas\n\nSi lees esto, el correo funciona.\n' | sendmail -v root
  tail -20 /var/log/mail.log      # busca "status=sent"
  mailq                           # no debe haber mensajes atascados

Revisa también la carpeta de spam del buzón de destino.
EOF
