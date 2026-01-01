#!/bin/bash
#
# Script de instalación para Nginx Reverse Proxy de HP iLO 5
#
# Uso: sudo ./install.sh <dominio> <ip_ilo>
# Ejemplo: sudo ./install.sh ilo.miempresa.com 192.168.1.100
#

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Este script debe ejecutarse como root${NC}"
    echo "Uso: sudo $0 <dominio> <ip_ilo>"
    exit 1
fi

# Verificar argumentos
if [ $# -ne 2 ]; then
    echo -e "${YELLOW}Uso: $0 <dominio> <ip_ilo>${NC}"
    echo "Ejemplo: $0 ilo.miempresa.com 192.168.1.100"
    exit 1
fi

DOMAIN=$1
ILO_IP=$2

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}  Instalador de Nginx Reverse Proxy para iLO 5${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""
echo "Dominio: $DOMAIN"
echo "IP iLO:  $ILO_IP"
echo ""

# Verificar nginx
if ! command -v nginx &> /dev/null; then
    echo -e "${RED}Error: Nginx no está instalado${NC}"
    exit 1
fi

# Backup de nginx.conf
echo -e "${YELLOW}[1/4] Haciendo backup de nginx.conf...${NC}"
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d%H%M%S)

# Verificar si el map ya existe
if grep -q 'map.*http_upgrade.*connection_upgrade' /etc/nginx/nginx.conf; then
    echo "      Map ya existe en nginx.conf"

    # Verificar si es "Upgrade" o "upgrade"
    if grep -q 'default upgrade;' /etc/nginx/nginx.conf; then
        echo -e "${YELLOW}      Corrigiendo 'upgrade' a 'Upgrade' (case-sensitive)...${NC}"
        sed -i 's/default upgrade;/default Upgrade;/' /etc/nginx/nginx.conf
    fi
else
    echo "      Agregando map a nginx.conf..."
    # Insertar el map después de "http {"
    sed -i '/http {/a\
    \
    # Map para WebSocket - iLO requiere "Upgrade" con U mayúscula\
    map $http_upgrade $connection_upgrade {\
        default Upgrade;\
        '\'''\'' close;\
    }' /etc/nginx/nginx.conf
fi

# Crear configuración del sitio
echo -e "${YELLOW}[2/4] Creando configuración del sitio...${NC}"

cat > /etc/nginx/sites-available/ilo << EOF
server {
    server_name ${DOMAIN};

    error_log /var/log/nginx/ilo-443-error.log;
    access_log /var/log/nginx/ilo-443-access.log;

    proxy_ssl_verify off;
    proxy_ssl_server_name off;
    proxy_ssl_protocols TLSv1.2 TLSv1.3;

    location ^~ /wss/ {
        proxy_pass https://${ILO_IP};
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$proxy_host;

        proxy_pass_request_headers on;

        proxy_read_timeout 1800s;
        proxy_send_timeout 1800s;
        proxy_connect_timeout 60s;
        proxy_buffering off;
        proxy_cache off;
        proxy_request_buffering off;

        proxy_ssl_session_reuse off;
    }

    location / {
        proxy_pass https://${ILO_IP};
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$proxy_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_cookie_domain ${ILO_IP} ${DOMAIN};
        proxy_cookie_path / /;

        proxy_buffering off;
        client_max_body_size 0;
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        send_timeout 3600s;
    }

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    listen 80;
}
EOF

# Habilitar sitio
echo -e "${YELLOW}[3/4] Habilitando sitio...${NC}"
if [ ! -d /etc/nginx/sites-enabled ]; then
    mkdir -p /etc/nginx/sites-enabled
fi

ln -sf /etc/nginx/sites-available/ilo /etc/nginx/sites-enabled/ilo

# Probar y recargar
echo -e "${YELLOW}[4/4] Probando configuración...${NC}"
if nginx -t; then
    nginx -s reload
    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}  Instalación completada exitosamente${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    echo "Próximos pasos:"
    echo ""
    echo "1. Configurar DNS para que ${DOMAIN} apunte a este servidor"
    echo ""
    echo "2. Obtener certificado SSL con Let's Encrypt:"
    echo "   sudo certbot --nginx -d ${DOMAIN}"
    echo ""
    echo "3. Acceder a: https://${DOMAIN}"
    echo ""
else
    echo -e "${RED}Error en la configuración de nginx${NC}"
    exit 1
fi
