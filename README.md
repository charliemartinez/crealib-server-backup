# Crealib Server Backup (CSB)
**Autor:** Charlie Martínez
**Licencia:** GPLv2

![Crealib Server Backup](https://charliemartinez.com.ar/wp-content/uploads/2023/11/crealib-server-backup_charlie-martinez.jpg)


## Documentación

- Este programa escanea los sitios que tenemos en nuestro servidor Apache, junto con sus BBDD y los ficheros de configuración de los virtualhosts.
- Guarda las carpetas de los sitios en archivadores .tar.gz individuales y los .sql en la raíz en carpetas correspondientes a su año/mes.
- En modo manual, permite elegir qué sitios, bases de datos y ficheros de configuración de virtualhost respaldar.
- Finalizada la ejecución, informa lo realizado y almacena esa información en un LOG progresivo.

### Configuración:

Los siguientes comandos deben ejecutarse desde el usuario root o mediante "sudo":

1. Establecer las rutas de almacenamiento de los respaldos, logs y las credenciales del usuario root de BBDD,<br> en el apartado CONFIGURACIÓN del código:

```sh
nano backup.sh
```
Contenido del fichero:
```sh
# ************************************* CONFIGURACIÓN *************************************

# Definir rutas de almacenamiento de backups y log:

BACKUP_DIR="/ruta/BACKUP_SERVER"
LOG_FILE="/ruta/backup_log.txt"

# Definir usuario y contraseña root de BBDD:

user="bd_usuario"
pass="Contraseña"

# *****************************************************************************************
```

Para guardar los backups se recomienda utilizar un disco distinto que el principal.

2. Convertir este script en un comando:

```sh
mv backup.sh /usr/local/bin/backup
```

3. Otorgar permisos de ejecución al comando:

```sh
chmod +x /usr/local/bin/backup
```

4. Crear excepción en **/etc/sudoers.d/backup** para que no solicite contraseña a crontab:

```sh
nano /etc/sudoers/backup
```
Contenido del fichero:
```sh
ALL ALL=NOPASSWD: /usr/local/bin/backup
```

5. Crear tarea programada, para que se ejecute una vez por mes:

```sh
crontab -u root -e
```
Contenido del fichero:
```sh
0 2 1 * * /usr/local/bin/backup
```

### Manual de uso

#### Modo automático / Respaldo total: 

Cron lo ejecutará en modo automático, del mismo modo que podemos ejecutarlo nosotros cuando necesitemos hacer un backup de TODO en un momento fuera del programado, utilizando el comando:

```sh
0 2 1 * * /usr/local/bin/backup
```

#### Modo manual / Respaldo selectivo:

En lugar de respaldar todo, CSB nos mostrará un menú para que podamos elegir cuales son los sitios, bases de datos y ficheros de configuración de virtualhost que queremos resguardar. 
Basta con añadir el modificador --manual de la siguiente manera:

```sh
backup --manual
```
También válido:

```sh
backup -m
```
