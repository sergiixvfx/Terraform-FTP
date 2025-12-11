#!/usr/bin/env bash
set -euxo pipefail

# Instalar vsftpd y pam_mysql
apt-get update -y
apt-get install -y vsftpd libpam-mysql

systemctl enable vsftpd
systemctl start vsftpd

# Crear usuario del sistema para mapear usuarios virtuales
adduser --system --home /home/vsftpd --group --shell /bin/false vsftpd || true

# Crear carpeta para el usuario virtual 'alumno'
mkdir -p /home/vsftpd/alumno
chown -R vsftpd:nogroup /home/vsftpd/alumno
chmod 755 /home/vsftpd/alumno

# Configuración PAM para vsftpd
cat >/etc/pam.d/vsftpd <<EOF
auth    required pam_listfile.so item=user sense=deny file=/etc/ftpusers onerr=succeed
auth    required pam_mysql.so user=ftpuser passwd=ftp  host=${bd_private_ip} db=vsftpd table=usuarios usercolumn=nombre passwdcolumn=passwd crypt=2
account required pam_mysql.so user=ftpuser passwd=ftp  host=${bd_private_ip} db=vsftpd table=usuarios usercolumn=nombre passwdcolumn=passwd crypt=2
EOF

# Script para actualizar IP Publica (AWS IMDSv2)
cat <<'EOSCRIPT' > /usr/local/bin/update_ftp_ip.sh
#!/bin/bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

if [[ ! -z "$PUBLIC_IP" ]]; then
    sed -i '/^pasv_address=/d' /etc/vsftpd.conf
    echo "pasv_address=$PUBLIC_IP" >> /etc/vsftpd.conf
    systemctl restart vsftpd
fi
EOSCRIPT
chmod +x /usr/local/bin/update_ftp_ip.sh

# Configuración vsftpd base
cat >/etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO

anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES

guest_enable=YES
guest_username=vsftpd
user_sub_token=\$USER
local_root=/home/vsftpd/\$USER
pam_service_name=vsftpd

virtual_use_local_privs=YES

# Configuración Pasiva
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_addr_resolve=NO

xferlog_enable=YES
log_ftp_protocol=YES
vsftpd_log_file=/var/log/vsftpd.log

utf8_filesystem=YES
EOF

# Ejecutar actualizacion de IP inicial
/usr/local/bin/update_ftp_ip.sh

# Programar en cron para reboots
(crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/update_ftp_ip.sh") | crontab -

