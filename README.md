# Despliegue Automatizado de Infraestructura FTP con Backend MySQL en AWS mediante Terraform

## 1. Introducción

Este repositorio documenta el procedimiento y contiene el código fuente necesario para el despliegue automatizado de una infraestructura de red en AWS utilizando Terraform.

El proyecto tiene como objetivo levantar un servicio FTP de alta disponibilidad y seguridad. Para ello, se utilizan dos instancias EC2 independientes: una dedicada al servicio FTP (`vsftpd`) y otra dedicada al motor de base de datos (`MariaDB`), garantizando la persistencia y centralización de credenciales.

## 2. Como se ha hecho

La infraestructura se despliega en la región `us-east-1` y se compone de los siguientes elementos:

* **Servidor Frontend (FTP):** Instancia EC2 expuesta a internet mediante una Elastic IP. Encargada de gestionar las conexiones de los clientes y la transferencia de datos.
* **Servidor Backend (Base de Datos):** Instancia EC2 aislada del acceso público directo. Almacena la base de datos `vsftpd` con la tabla de usuarios virtuales.
* **Red y Seguridad:** Se utiliza la VPC por defecto, aplicando una segmentación estricta mediante Grupos de Seguridad (Security Groups) para controlar el tráfico entrante y saliente.

## 3. Descripción del Terraform

El archivo `main.tf` orquesta la creación de los recursos. A continuación, se detalla la configuración y justificación de cada componente:

### 3.1. Selección de imagen
Se utiliza un `data source` para localizar dinámicamente la última versión disponible de **Ubuntu 24.04 LTS (HVM)**.

### 3.2. Grupos de seguridad
Se han definido dos grupos de seguridad para aplicar el principio de mínimo privilegio:

* **`mysql_firewall`**
    * Permite tráfico SSH (puerto 22) para administración.
    * Permite tráfico MySQL (puerto 3306) **exclusivamente** desde el bloque CIDR de la VPC (`172.31.0.0/16`). Esto impide cualquier intento de conexión a la base de datos desde una IP pública externa.
* **`vsftpd_firewall`**
    * Permite tráfico SSH (puerto 22).
    * Permite tráfico de control FTP (puerto 21).
    * Permite tráfico de datos pasivos (rango **40000-40100**). Este rango es necesario para establecer la comunicación de datos en modo pasivo.

### 3.3. Elastic IP
Se asigna una dirección IP estática pública a la instancia FTP.

### 3.4. Inyección de configuración
Se utiliza la propiedad `user_data` de las instancias EC2 para ejecutar scripts de aprovisionamiento en el primer arranque:
* La instancia de base de datos carga directamente el archivo `scripts/mysql.sh`.
* La instancia de FTP utiliza la función `templatefile` para cargar `scripts/ftp.sh`. Esto permite inyectar variables de Terraform (como la `private_ip` de la base de datos) dentro del script de bash antes de su ejecución.

## 4. Scripts

La configuración interna de los servidores se realiza de forma automática mediante los siguientes scripts de shell.

### 4.1. Configuración de Base de Datos (`scripts/mysql.sh`)
Este script transforma una instancia Ubuntu estándar en el servidor de autenticación.

1.  **Instalación:** Despliega el paquete `mariadb-server`.
2.  **Configuración de Escucha:** Modifica el archivo `/etc/mysql/mariadb.conf.d/50-server.cnf` cambiando el parámetro `bind-address` a `0.0.0.0`. Esto es mandatorio para permitir que el servidor acepte conexiones externas (específicamente, desde el servidor FTP).
3.  **Estructura de Datos:** Genera la base de datos `vsftpd` y la tabla `usuarios` (columnas: id, nombre, passwd).
4.  **Usuario de Servicio:** Crea el usuario SQL `ftpuser` con permisos restringidos (`GRANT SELECT`). Este usuario será el utilizado por el servicio FTP para validar las contraseñas.
5.  **Datos de Prueba:** Inserta un usuario inicial (`alumno`) con la contraseña encriptada.

### 4.2. Configuración de Servidor FTP (`scripts/ftp.sh`)
Este script configura `vsftpd` para utilizar usuarios virtuales y manejar la conectividad en la nube de AWS.

1.  **Integración PAM-MySQL:** Instala `libpam-mysql` y configura el archivo `/etc/pam.d/vsftpd`. Utiliza la variable inyectada por Terraform `${bd_private_ip}` para direccionar las peticiones de autenticación hacia la instancia de base de datos.
2.  **Usuarios Virtuales:** Crea un usuario de sistema sin privilegios (`vsftpd`) al cual se mapean todos los usuarios FTP virtuales. Se fuerza el enjaulamiento (`chroot`) de los usuarios en su directorio local para evitar el acceso al sistema de archivos raíz.
3.  **Configuración de Modo Pasivo (AWS IMDSv2):**
    * Para funcionar correctamente detrás de NAT (AWS), el servidor FTP debe conocer su IP pública.
    * El script genera un ejecutable interno (`/usr/local/bin/update_ftp_ip.sh`) que consulta la API de Metadatos de Instancia de AWS.
    * Obtiene la IP pública y actualiza dinámicamente el parámetro `pasv_address` en `vsftpd.conf`.
    * Se configura una tarea en `cron` (`@reboot`) para asegurar la persistencia de esta configuración ante reinicios.

---

## 5. Instrucciones de Despliegue

### Requisitos Previos
* Terraform instalado (versión >= 1.5.0).
* AWS CLI configurado con credenciales válidas.
* Un par de claves SSH (Key Pair) existente en AWS llamado `vockey`.

### Procedimiento

1.  **Inicialización del entorno:**
    Descarga los proveedores de AWS necesarios para la ejecución.
    ```bash
    terraform init
    ```

2.  **Planificación:**
    Genera un plan de ejecución para previsualizar los recursos que serán creados.
    ```bash
    terraform plan
    ```

3.  **Aplicación:**
    Ejecuta la creación de la infraestructura.
    ```bash
    terraform apply -auto-approve
    ```

---

## 6. Validación y Pruebas

Una vez finalizado el comando `terraform apply`, se mostrarán en la consola las direcciones IP resultantes. Utilice los siguientes datos para verificar el funcionamiento:

**Datos de Conexión FTP:**
* **Host:** Utilice la IP mostrada en el output `ftp_elastic_ip`.
* **Protocolo:** FTP (File Transfer Protocol).
* **Cifrado:** Usar FTP plano (inseguro) o FTP explícito sobre TLS si está disponible.
* **Modo de Transferencia:** Pasivo.
* **Usuario:** `alumno`
* **Contraseña:** `1234`

