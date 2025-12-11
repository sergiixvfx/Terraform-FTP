#!/bin/bash
apt-get update -y
apt-get install -y mariadb-server

systemctl enable mariadb
systemctl start mariadb

sed -i 's/^bind-address.*/bind-address=0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf || true
systemctl restart mariadb

mysql <<EOF
CREATE DATABASE IF NOT EXISTS vsftpd CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE vsftpd;

CREATE TABLE IF NOT EXISTS usuarios (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(64) NOT NULL UNIQUE,
  passwd VARCHAR(255) NOT NULL
);

INSERT IGNORE INTO usuarios (nombre, passwd) VALUES ('alumno', PASSWORD('1234'));

CREATE USER IF NOT EXISTS 'ftpuser'@'%' IDENTIFIED BY 'ftp';
GRANT SELECT (nombre, passwd) ON vsftpd.usuarios TO 'ftpuser'@'%';
FLUSH PRIVILEGES;
EOF