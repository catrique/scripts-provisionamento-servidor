#!/bin/bash

set -e

NGINX_CONFIG="/caminho/para/seu/arquivo/nginx.conf"
IP="IP onde o serviço será executado"
BACKUP_DIR="/caminho/para/diretorio/de/backup"
BACKUP_FILE="$BACKUP_DIR/nginx-default.backup"


if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <porta> <api>"
    echo
    echo "Exemplo:"
    echo "sudo $0 8001 api-teste"
    exit 1
fi

PORTA="$1"
API="$2"

echo "================================="
echo " Provisionando Backend"
echo "================================="
echo "API:    $API"
echo "Porta:  $PORTA"
echo "Rota:   /$API/"
echo

echo "Verificando porta $PORTA..."

if sudo lsof -i :"$PORTA" -sTCP:LISTEN -t >/dev/null; then
    echo
    echo "Erro: a porta $PORTA já está em uso."
    echo
    echo "Processo utilizando a porta:"
    sudo lsof -i :"$PORTA" -sTCP:LISTEN
    exit 1
fi

echo "Porta $PORTA está disponível."

echo
echo "Verificando rota /$API/..."

if grep -q "location /$API/" "$NGINX_CONFIG"; then
    echo
    echo "Erro: a rota /$API/ já está configurada no Nginx."
    exit 1
fi

echo "Rota /$API/ está disponível."

echo
echo "Fazendo backup do Nginx..."

cp "$NGINX_CONFIG" "$BACKUP_FILE"

echo "Backup criado em:"
echo "$BACKUP_FILE"

echo
echo "Adicionando configuração ao Nginx..."

LOCATION="
        # $API

        location /$API/ {
                proxy_pass http://$IP:$PORTA/;
                proxy_http_version 1.1;

                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \$scheme;
                proxy_set_header X-Forwarded-Prefix /$API;

                proxy_connect_timeout 60s;
                proxy_read_timeout 1200s;
                proxy_send_timeout 1200s;
                client_max_body_size 50m;
        }
"

head -n -1 "$NGINX_CONFIG" > /tmp/nginx.conf

cat >> /tmp/nginx.conf <<EOF

$LOCATION

EOF

echo "}" >> /tmp/nginx.conf

cp /tmp/nginx.conf "$NGINX_CONFIG"

echo
echo "Validando Nginx..."

if ! nginx -t; then
    echo
    echo "Erro na configuração do Nginx."
    echo "Restaurando backup..."

    cp "$BACKUP_FILE" "$NGINX_CONFIG"

    echo "Backup restaurado."
    exit 1
fi

echo
echo "Configuração do Nginx válida."

echo
echo "Recarregando Nginx..."

systemctl reload nginx

echo
echo "================================="
echo " Backend provisionado com sucesso!"
echo "================================="
echo
echo "API:    $API"
echo "Porta:  $PORTA"
echo "Rota:   /$API/"
