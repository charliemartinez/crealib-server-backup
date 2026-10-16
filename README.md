# CSB – CREALIB SERVER BACKUP (edición Proxmox)

Copias de seguridad de sitios web (WordPress y otros) y bases de datos que viven en **contenedores LXC de Proxmox**, ejecutadas desde el **host** con `pct exec`. Incluye rotación automática y alertas por correo.

- **Sitios**: un `tar.gz` por cada carpeta de `/var/www` del contenedor web.
- **Bases de datos**: se detectan leyendo `DB_NAME` de cada `wp-config.php` (también en subcarpetas) y se vuelcan con `mariadb-dump --single-transaction`. Opcionalmente, PostgreSQL con `pg_dumpall`.
- **Apache**: copia de `sites-available/enabled` y `conf-available/enabled` del contenedor web y del proxy.
- **Integridad**: cada copia lleva sumas SHA-256 y se verifica al crearla (gzip, tar y última línea del volcado).
- **Restauración** de sitio completo, solo ficheros, solo base de datos o configuración de Apache. Antes de restaurar guarda el estado actual como una copia nueva; si Apache no valida la configuración restaurada, deshace el cambio.
- **Menús** con `dialog` (`csb --manual`, `csb --gestionar`).
- **Rotación** con `csb-prune`, con salvaguardas para no borrar nunca por error.

## Requisitos

- Host Proxmox VE con `pct` y acceso como root.
- Un contenedor con Apache y los sitios (`WEB_CT`), otro con MariaDB (`DB_CT`) y, opcionalmente, un proxy (`PROXY_CT`).
- Un destino montado para las copias (por ejemplo, un dataset ZFS). Por defecto el script **se niega a escribir si el destino no es un punto de montaje**, para no llenar el disco del sistema.
- `dialog` solo si quieres usar los menús (`apt install dialog`).

## Instalación

```bash
git clone https://github.com/charliemartinez/crealib-server-backup.git
cd crealib-server-backup
./install.sh
```

Ajusta la configuración con variables de entorno (o editando la sección *CONFIGURACIÓN* de `csb`):

| Variable | Por defecto | Descripción |
|---|---|---|
| `WEB_CT` | `101` | Contenedor con los sitios web |
| `DB_CT` | `103` | Contenedor con MariaDB (y PostgreSQL) |
| `PROXY_CT` | `100` | Contenedor proxy (vacío para omitirlo) |
| `WWW_DIR` | `/var/www` | Carpeta de sitios dentro de `WEB_CT` |
| `BACKUP_DIR` | `/mnt/pool-bulk/backups-sitios` | Destino de las copias |
| `REQUIRE_MOUNTPOINT` | `1` | Exige que `BACKUP_DIR` sea un punto de montaje |
| `MIN_FREE_GB` | `20` | No crea copias si queda menos espacio libre |
| `BACKUP_POSTGRES` | `1` | Incluye PostgreSQL |

Ejemplo: `BACKUP_DIR=/mnt/otro/destino WEB_CT=200 csb --listar`

## Uso

```bash
csb                                   # copia completa
csb --sitio ejemplo.org               # un sitio con sus bases de datos
csb --listar                          # sitios y la base de datos de cada uno
csb --copias                          # lista las copias
csb --verificar 2026-10-15_03-00-01   # comprueba integridad
csb --restaurar sitio FECHA ejemplo.org
csb --restaurar archivos FECHA ejemplo.org
csb --restaurar bd FECHA nombre_bd
csb --restaurar apache FECHA 101
csb --manual                          # menú interactivo
```

Las copias se guardan como `BACKUP_DIR/AAAA/MM/FECHA_NOMBRE.{tar.gz,sql.gz}`. Añade `--si` para no pedir confirmación en operaciones destructivas.

> La base de sistema `mysql` (usuarios y permisos) se respalda, pero **no se restaura automáticamente**: hazlo a mano.

## ¿Diaria, semanal o mensual?

`csb` hace una copia **completa** cada vez, sin deduplicar, y los `.gz` no se comprimen más con ZFS. El espacio necesario es *tamaño de una copia × copias al mes × meses a conservar*. Ejemplo con copias de 1,7 GB:

| Frecuencia, sin borrar nunca | Consumo al año |
|---|---|
| Diaria | ~620 GB |
| Semanal | ~88 GB |
| Mensual | ~20 GB |

Por eso la combinación recomendada es **diaria + rotación** con `csb-prune`: 14 días completos + la mejor copia de cada uno de los últimos 12 meses (unas 26 copias, ~44 GB con ese tamaño). Mide el tamaño de **tu** copia (`csb --copias`) y ajusta `KEEP_DAYS` y `KEEP_MONTHS`.

## Rotación (`csb-prune`)

```bash
csb-prune             # simulación: muestra qué borraría
csb-prune --aplicar   # borra
```

Variables: `KEEP_DAYS` (14), `KEEP_MONTHS` (12), `MIN_SETS` (3), `MIN_FILES_FULL` (20), `BACKUP_DIR`, `CSB_BIN`.

Salvaguardas: si no hay una copia completa (≥ `MIN_FILES_FULL` ficheros) de los últimos 2 días, no borra nada; y siempre deja al menos `MIN_SETS` copias. Las copias manuales y las de «estado previo a restaurar» también se rotan.

## Programar con cron

Prueba primero una copia a mano (`csb`) y comprueba que termina con `errores: 0`. Después:

```bash
./install.sh --cron
```

Instala `/etc/cron.d/csb`: copia diaria a las 03:00 y rotación justo después. Evita solapar con otras tareas pesadas (copias de Proxmox `vzdump`, snapshots, actualizaciones).

Comprobación al día siguiente:

```bash
grep 'CSB (auto)' /mnt/TU_DESTINO/backup_log.txt | tail -3
cat /var/log/csb-prune.log
csb --copias
```

## Alertas por correo

Con `MAILTO=root`, cron envía un correo cuando `csb` escribe algo por stderr; si todo va bien, no llega nada. Para que ese correo llegue a una dirección real:

```bash
SMTP_HOST=smtp.example.com SMTP_USER=alertas@example.com ALERT_TO=admin@example.org ./setup-mail-alerts.sh
```

Configura `postfix` como *relay* SMTPS (puerto 465), reescribe el remitente de `root` (muchos SMTP exigen que coincida con la cuenta autenticada) y redirige `root` a `ALERT_TO`. **Todos los valores del repositorio son ficticios**; la contraseña se pide por teclado y no se guarda en ningún fichero del repo.

Notas:
- Usa una cuenta de correo **dedicada** a avisos, con una contraseña que no uses en otro sitio. `/etc/postfix/sasl_passwd` queda en texto plano (modo 600).
- Si el SMTP cae o la contraseña cambia, los avisos se encolan sin llegar: revisa `mailq` de vez en cuando.
- Si el servidor rechaza con *Sender verify failed*, el remitente no se está reescribiendo: comprueba que el nombre en `/etc/postfix/sender_canonical` coincide con `postconf myhostname`.

## Limitaciones y buenas prácticas

- **Las copias están en el mismo servidor que los datos.** Un espejo ZFS protege de un disco roto, no de un borrado accidental, ransomware, fallo del host o incendio. Sincroniza `BACKUP_DIR` a otra máquina (`rsync`, `rclone`, `zfs send`).
- **Prueba las restauraciones** en un entorno de pruebas de vez en cuando. Una copia que nunca se ha restaurado no es una garantía.
- Los sitios activos pueden cambiar mientras se copian (el aviso «file changed as we read it» se ignora a propósito). Las bases de datos se vuelcan con `--single-transaction`, que es coherente para InnoDB.
- Los volcados de PostgreSQL contienen hashes de contraseñas de roles; las copias se crean con `umask 077` (solo root).

## Notas sobre PostgreSQL

`pg_dumpall` termina con `-- PostgreSQL database cluster dump complete`, seguido de `--` y una línea en blanco (las versiones recientes añaden además `\unrestrict`). Por eso la comprobación mira las **últimas 5 líneas** y no solo la última. Además, el volcado se ejecuta con `cd /tmp` para evitar el aviso `could not change directory to "/root"` de `su postgres`.

## Licencia

GNU General Public License v2. Consulta [`LICENSE`](LICENSE).

Basado en CSB 2.1 de Charlie Martínez &lt;cmartinez@crealib.net&gt;.
