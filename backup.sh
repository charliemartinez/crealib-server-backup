#!/bin/bash
# CREALIB SERVER BACKUP (CSB) Ver. 2.1
# Autor: Charlie Martínez <cmartinez@crealib.net>
# Licencia: GPLv2
# Cambios versión 2.1: Ya no borra luego de 5 años y ahora no hace uso del comando "mv"; se agregan comprobaciones.

# ********************************************************* DOCUMENTACIÓN *********************************************************

# https://github.com/charliemartinez/server-backup/tree/main#readme

# ********************************************************** CONFIGURACIÓN ********************************************************

# Definir rutas de almacenamiento de backups:

BACKUP_DIR="/ruta/BACKUP_SERVER" 

# Definir ruta de almacenamiento y nombre del log:

LOG_FILE="/ruta/BACKUP_SERVER/backup_log.txt"

# Definir usuario y contraseña root de BBDD:

user="us_bbdd"
pass="Contraseña"

# Definir carpeta de sitios a respaldar, predeterminada: "/var/www"

WWW_DIR="/var/www" 

# Definir carpeta de ficheros .conf, predeterminada: "/etc/apache2/sites-available"

VIRTUALHOSTS_DIR="/etc/apache2/sites-available"

# Formato de fecha y hora:
DATE=$(date +'%Y-%m-%d_%H-%M')
MONTH=$(date +'%m')
YEAR=$(date +'%Y')

# ******************************************************** COMPROBACIONES *********************************************************

# Verifica y el directorio de almacenamiento si no existen

if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "$DATE : Directorio $BACKUP_DIR creado." >> "$LOG_FILE"
fi

# Verifica y crea archivo de LOG si no existe

if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    echo "CREALIB SERVER BACKUP (CSB)" >> "$LOG_FILE"
    echo "Registro de Backups realizados" >> "$LOG_FILE"
    echo " " >> "$LOG_FILE"
    echo "$DATE : Creación del directorio de almacenamiento." >> "$LOG_FILE"
    echo "$DATE : Creación del archivo de registro." >> "$LOG_FILE"
fi

# Verifica la existencia de los comandos tar, gzip, MySQL/MariaDB, mkdir, dialog y cp

dependencies=("tar" "gzip" "mkdir" "cp" "dialog")
missing_dependencies=()

for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        missing_dependencies+=("$dep")
    fi
done

if [ ${#missing_dependencies[@]} -gt 0 ]; then
    echo "Advertencia: Las siguientes dependencias no están instaladas y serán instaladas automáticamente: ${missing_dependencies[*]}"
    for dep in "${missing_dependencies[@]}"; do
        install_dependency "$dep"
    done
fi

# Instalación de dependencias

install_dependency() {
    dep="$1"
    case "$dep" in
        "tar")
            echo "Instalando tar..."
            apt-get install -y tar
            echo "$DATE : Instalación de tar, dependencia necesaria." >> "$LOG_FILE"
            ;;
        "gzip")
            echo "Instalando gzip..."
            apt-get install -y gzip
            echo "$DATE : Instalación de gzip, dependencia necesaria." >> "$LOG_FILE"
            ;;
        "mkdir")
            echo "Instalando mkdir..."
            apt-get install -y coreutils
            echo "$DATE : Instalación de coreutils, dependencia necesaria." >> "$LOG_FILE"
            ;;
        "cp")
            echo "Instalando cp..."
            apt-get install -y coreutils
            echo "$DATE : Instalación de coreutils, dependencia necesaria." >> "$LOG_FILE"
            ;;
		"dialog")
           echo "Instalando dialog..."
           apt-get install -y coreutils
           echo "$DATE : Instalación de dialog, dependencia necesaria." >> "$LOG_FILE"
           ;;
            
        *)
            echo "Advertencia: No se pudo instalar la dependencia desconocida: $dep"
            ;;
    esac
}

# Verifica si está instalado MySQL o MariaDB

if command -v "mysql" &>/dev/null || command -v "mariadb" &>/dev/null; then
    echo "MySQL o MariaDB ya está instalado."
else
    echo "Advertencia: Ni MySQL ni MariaDB están instalados. Instalando MariaDB..."
    apt-get install -y mariadb-server
    echo "$DATE : Instalación de mariadb-server, dependencia necesaria." >> "$LOG_FILE"
fi

# Verifica si existe carpeta del año en curso y si no la crea:

CURRENT_YEAR_DIR="$BACKUP_DIR/$YEAR"
if [ ! -d "$CURRENT_YEAR_DIR" ]; then

    # Crea carpeta del año en curso
    
    mkdir -p "$CURRENT_YEAR_DIR"
    echo "$DATE : Carpeta del año en curso creada: $CURRENT_YEAR_DIR" >> "$LOG_FILE"
fi

# Verifica si existe carpeta del mes actual y si no la crea:

CURRENT_MONTH_DIR="$CURRENT_YEAR_DIR/$MONTH"
if [ ! -d "$CURRENT_MONTH_DIR" ]; then
    mkdir -p "$CURRENT_MONTH_DIR"
    echo "$DATE : Carpeta del mes actual creada: $CURRENT_MONTH_DIR" >> "$LOG_FILE"
fi

# Verifica si existen sitios, ofreciendo una salida distinta si se ejecuta en modo manual o automático

function check_sitios() {
    SITE_COUNT=$(find "$WWW_DIR" -maxdepth 1 -type d | wc -l)

    if [ "$SITE_COUNT" -eq 1 ]; then
        if [ "$1" == "manual" ]; then
            dialog --msgbox "Advertencia: No se encontraron sitios en $WWW_DIR." 10 40
        else
            echo "Advertencia: $DATE : no se encontraron sitios en $WWW_DIR." >> "$LOG_FILE"
        fi
        return 1
    fi

    return 0
}

# Verifica si existen configuraciones de VirtualHosts, ofreciendo una salida distinta si se ejecuta en modo manual o automático

function check_conf_virtualhosts() {
    CONF_COUNT=$(find "$VIRTUALHOSTS_DIR" -maxdepth 1 -type f -name "*.conf" | wc -l)

    if [ "$CONF_COUNT" -eq 0 ]; then
        if [ "$1" == "manual" ]; then
            dialog --msgbox "Advertencia: No se encontraron archivos .conf en $VIRTUALHOSTS_DIR." 10 40
        else
            echo "Advertencia: $DATE : no se encontraron archivos .conf en $VIRTUALHOSTS_DIR." >> "$LOG_FILE"
        fi
        return 1
    fi

    return 0
}

# Verifica si existen bases de datos, ofreciendo una salida distinta si se ejecuta en modo manual o automático

function check_bbdd() {
    DATABASE_COUNT=$(mysql -u "$user" -p"$pass" -e "SHOW DATABASES" | awk '{print $1}' | grep -v "^Database$" | wc -l)

    if [ "$DATABASE_COUNT" -eq 0 ]; then
        if [ "$1" == "manual" ]; then
            dialog --msgbox "Advertencia: No se encontraron bases de datos." 10 40
        else
            echo "Advertencia: $DATE : no se encontraron bases de datos." >> "$LOG_FILE"
        fi
        return 1
    fi

    return 0
}

# ******************************************************** ESCANEO *********************************************************

# Escanea y agrega automáticamente los archivos .conf a su array

CONF_FILES=()
for conf_file in "$VIRTUALHOSTS_DIR"/*.conf; do
    CONF_FILES+=("$(basename "$conf_file")")
done

# Escanea y agrega automáticamente los sitios a su array

SITIOS=("$WWW_DIR"/*)
for folder in $(find "$WWW_DIR" -maxdepth 1 -type d); do
    SITIOS+=("$(basename "$folder")")
done

# Escanea y agrega automáticamente las bases de datos a su array

DATABASES=($(mysql -u "$user" -p"$pass" -e "show databases" | awk '{print $1}' | grep -v "^Database$"))

# ******************************************************** MODO MANUAL *********************************************************

if [[ "$1" == "--manual" || "$1" == "-m" ]]; then # Modo manual: "backup --manual" ó "backup -m"

    # Comprobar si existen sitios
    
    if check_sitios "manual"; then
    
        # Genera las opciones de menú para la selección de sitios
        
        folder_options=()
        for ((i = 0; i < ${#SITIOS[@]}; i++)); do
            folder="${SITIOS[$i]}"
            folder_name=$(basename "$folder") # Obtener el nombre base
            folder_options+=("$i" "$folder_name" off)
        done

        selected_folders=$(dialog --title "[Desplazarse: <🡡> <🡣>][Seleccionar: <Space>]" --backtitle "CREALIB SERVER BACKUP (CSB) 2023 By Charlie Martínez" \
            --stdout \
            --checklist "Sitios a respaldar:" 15 50 5 "${folder_options[@]}")

        # Cierra el descriptor de archivo para dialog
        exec 3>&1
    fi

    # Comprobar si existen bases de datos
    
    if check_bbdd "manual"; then
    
        # Genera las opciones de menú para la selección de bases de datos
        
        database_options=()
        for ((i = 0; i < ${#DATABASES[@]}; i++)); do
            database_options+=("$i" "${DATABASES[$i]}" off)
        done

        selected_databases=$(dialog --title "[Desplazarse: <🡡> <🡣>][Seleccionar: <Space>]" --backtitle "CREALIB SERVER BACKUP (CSB) 2023 By Charlie Martínez" \
            --stdout \
            --checklist "Bases de datos a respaldar:" 15 50 5 "${database_options[@]}")

        # Cierra el descriptor de archivo para dialog
        
        exec 3>&-
    fi

    # Comprobar si existen configuraciones de VirtualHosts
    
    if check_conf_virtualhosts "manual"; then
    
        # Genera las opciones de menú para la selección de archivos .conf (virtualhosts)
        
        conf_options=()
        for ((i = 0; i < ${#CONF_FILES[@]}; i++)); do
            conf_file="${CONF_FILES[$i]}"
            conf_options+=("$i" "$conf_file" off)
        done

        selected_conf_files=$(dialog --title "[Desplazarse: <🡡> <🡣>][Seleccionar: <Space>]" --backtitle "CREALIB SERVER BACKUP (CSB) 2023 By Charlie Martínez" \
            --stdout \
            --checklist "Configuraciones de VirtualHosts a respaldar:" 15 50 5 "${conf_options[@]}")
    fi

    # Crea un respaldo de las carpetas seleccionadas en archivos tar.gz individuales
        
		backup_files=()
    
		for index in $selected_folders; do
			folder="${SITIOS[index]}"
			folder_name=$(basename "$folder")
			TAR_FILE="${DATE}_${folder_name}.tar.gz"

			# Utiliza las variables $YEAR y $MONTH para determinar la ubicación de almacenamiento
			
			tar -czvf "$BACKUP_DIR/$YEAR/$MONTH/$TAR_FILE" -C "$WWW_DIR" "$folder_name"
			backup_files+=("$TAR_FILE")
		done

	# Crea un respaldo de las bases de datos seleccionadas en archivos SQL individuales
				
		for index in $selected_databases; do
			database="${DATABASES[index]}"
			SQL_FILE="${DATE}_${database}.sql"

			# Utiliza las variables $YEAR y $MONTH para determinar la ubicación de almacenamiento
			
			mysqldump -u "$user" -p"$pass" "$database" > "$BACKUP_DIR/$YEAR/$MONTH/$SQL_FILE"
			backup_files+=("$SQL_FILE")
		done

    # Crea un respaldo de los archivos .conf de VirtualHosts seleccionados en archivos individuales
    
		for index in $selected_conf_files; do
			conf_file="${CONF_FILES[index]}"
			conf_filename="$(basename "$conf_file")"
			NEW_CONF_FILE="${DATE}_${conf_filename}"
			
			# Utiliza las variables $YEAR y $MONTH para determinar la ubicación de almacenamiento
			
			cp "$VIRTUALHOSTS_DIR/$conf_file" "$BACKUP_DIR/$YEAR/$MONTH/$NEW_CONF_FILE"
			backup_files+=("$NEW_CONF_FILE")
		done

    # Registrar los archivos respaldados en el archivo de log
    
		echo " " >> "$LOG_FILE"
		echo "=====================================================================================" >> "$LOG_FILE"
		echo "$DATE : Ejecución manual" >> "$LOG_FILE"
		echo "=====================================================================================" >> "$LOG_FILE"
		echo "Se crearon las siguientes copias de seguridad:" >> "$LOG_FILE"
		echo " " >> "$LOG_FILE"
		for file in "${backup_files[@]}"; do
			echo "$file" >> "$LOG_FILE"
		done

    # Saludo final del modo manual
    
		dialog --title "CREALIB SERVER BACKUP (CSB)" --msgbox "Contactar al autor: cmartinez@crealib.net www.charliemartinez.com.ar" 10 40
	
    # Limpia la pantalla y sale del script
    
		clear
		exit 0

else

	# ****************************************************** MODO AUTOMÁTICO ******************************************************
			   
		# Agrega el nuevo registro al archivo de LOG sin sobrescribir
		
		echo " " >> "$LOG_FILE"
		echo "=====================================================================================" >> "$LOG_FILE"
		echo "$DATE : Ejecución automática" >> "$LOG_FILE"
		echo "=====================================================================================" >> "$LOG_FILE"

	# Crea un respaldo de todos los sitios que existen:
	
	if check_sitios; then
		backup_files=()
		for folder in "${SITIOS[@]}"; do
			folder_name=$(basename "$folder")
			TAR_FILE="${DATE}_${folder_name}.tar.gz"
			
			# Utiliza las variables $YEAR y $MONTH para determinar la ubicación de almacenamiento
			
			tar -czvf "$BACKUP_DIR/$YEAR/$MONTH/$TAR_FILE" -C "$WWW_DIR" "$folder_name"
			backup_files+=("$TAR_FILE")
		done
	fi
	
	# Crea un respaldo de todos los ficheros de configuración de VirtualHosts que existen
	
	if check_conf_virtualhosts; then
		backup_files=()
		for conf_file in "${CONF_FILES[@]}"; do
			conf_filename=$(basename "$conf_file")
			NEW_CONF_FILE="${DATE}_${conf_filename}"
			
			# Utiliza las variables $YEAR y $MONTH para determinar la ubicación de almacenamiento
			cp "$VIRTUALHOSTS_DIR/$conf_file" "$BACKUP_DIR/$YEAR/$MONTH/$NEW_CONF_FILE"
			backup_files+=("$NEW_CONF_FILE")
		done
	fi

	# Crea un respaldo de todas las bases de datos que existen

	if check_bbdd; then
		backup_files=()
		for database in "${DATABASES[@]}"; do
			SQL_FILE="${DATE}_${database}.sql"
        
			# Utiliza las variables $YEAR y $MONTH para determinar la ubicación de almacenamiento
			mysqldump -u "$user" -p"$pass" "$database" > "$BACKUP_DIR/$YEAR/$MONTH/$SQL_FILE"
			backup_files+=("$SQL_FILE")
		done
	fi

	# Saludo final del modo automático y registro en el log
	
	echo "Se crearon las siguientes copias de seguridad:" >> "$LOG_FILE"
	echo " " >> "$LOG_FILE"

	for file in "${backup_files[@]}"; do
		echo "$file" >> "$LOG_FILE"
	done
fi
