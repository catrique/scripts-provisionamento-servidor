#!/bin/bash

set -e

BASE="/caminho/para/diretorio/base"
NGINX_CONFIG="/caminho/para/seu/arquivo/nginx.conf"
BACKUP_DIR="/caminho/para/diretorio/de/backup"
BACKUP_FILE="$BACKUP_DIR/nginx-default.backup"

if [ "$#" -ne 1 ]; then
    echo "Uso: $0 <nome>"
    echo
    echo "Exemplo: sudo $0 gerador-excel-controladoria"
    echo "O nome da pasta tambem sera usado na URL."
    exit 1
fi

NOME="$1"

if ! [[ "$NOME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "Erro: use apenas letras, numeros, ponto, hifen ou sublinhado no nome."
    exit 1
fi

PASTA="$BASE/$NOME"

if grep -Fq "location /$NOME/" "$NGINX_CONFIG"; then
    echo "Erro: a rota /$NOME/ ja esta configurada no Nginx."
    exit 1
fi

echo "Criando pasta $PASTA..."
mkdir -p "$PASTA"
echo "Pasta $PASTA criada."

echo "Fazendo backup do Nginx..."
mkdir -p "$BACKUP_DIR"
cp "$NGINX_CONFIG" "$BACKUP_FILE"
echo "Backup criado em: $BACKUP_FILE"

LOCATION="
        location = /$NOME {
                return 301 /$NOME/;
        }

        location /$NOME/ {
                alias $PASTA/;
                index index.html;
                try_files \$uri \$uri/ /$NOME/index.html;
        }
"

TEMP_CONFIG="$(mktemp)"
trap 'rm -f "$TEMP_CONFIG"' EXIT

if ! tail -n 1 "$NGINX_CONFIG" | grep -q '^[[:space:]]*}[[:space:]]*$'; then
    echo "Erro: a chave final da configuracao do Nginx nao foi encontrada."
    exit 1
fi

head -n -1 "$NGINX_CONFIG" > "$TEMP_CONFIG"
cat >> "$TEMP_CONFIG" <<EOF

$LOCATION

EOF
echo "}" >> "$TEMP_CONFIG"

cp "$TEMP_CONFIG" "$NGINX_CONFIG"

echo "Validando Nginx..."
if ! nginx -t; then
    echo "Erro na configuracao do Nginx. Restaurando backup..."
    cp "$BACKUP_FILE" "$NGINX_CONFIG"
    echo "Backup restaurado."
    exit 1
fi

echo "Recarregando Nginx..."
systemctl reload nginx

echo "Frontend provisionado com sucesso!"
