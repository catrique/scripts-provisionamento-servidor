#!/bin/bash

set -e

BASE="/caminho/para/diretorio/base"
USUARIO="seu_usuario"
HOME_USUARIO="/home/seu_usuario"

if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <pasta> <porta>"
    echo
    echo "Exemplo:"
    echo "sudo $0 api-empenhos 8001"
    exit 1
fi

API="$1"
PORTA="$2"
PASTA="$BASE/$API"

echo "================================="
echo " Provisionando API Node.js"
echo "================================="
echo "API:    $API"
echo "Pasta:  $PASTA"
echo "Porta:  $PORTA"
echo

# ==================================================
# Validações
# ==================================================

echo "Verificando pasta..."

if [ ! -d "$PASTA" ]; then
    echo "Erro: a pasta não existe:"
    echo "$PASTA"
    exit 1
fi

echo "Pasta encontrada."

echo
echo "Verificando package.json..."

if [ ! -f "$PASTA/package.json" ]; then
    echo "Erro: package.json não encontrado:"
    echo "$PASTA/package.json"
    exit 1
fi

echo "package.json encontrado."

echo
echo "Verificando script start..."

if ! node -e "
const pkg = require('$PASTA/package.json');

if (!pkg.scripts || !pkg.scripts.start) {
    process.exit(1);
}
"; then
    echo "Erro: o package.json não possui o script 'start'."
    echo
    echo 'Exemplo:'
    echo '"scripts": {'
    echo '    "start": "node src/server.js"'
    echo '}'
    exit 1
fi

echo "Script start encontrado."

echo
echo "Verificando porta $PORTA..."

if sudo lsof -i :"$PORTA" -sTCP:LISTEN -t >/dev/null; then
    echo
    echo "Erro: a porta $PORTA já está em uso."
    echo
    sudo lsof -i :"$PORTA" -sTCP:LISTEN
    exit 1
fi

echo "Porta $PORTA está disponível."

# ==================================================
# Dependências
# ==================================================

echo
echo "Instalando dependências..."

cd "$PASTA"

sudo -u "$USUARIO" npm install

# ==================================================
# PM2
# ==================================================

echo
echo "Verificando PM2..."

if ! command -v pm2 >/dev/null 2>&1; then
    echo "Erro: PM2 não está instalado."
    echo
    echo "Instale com:"
    echo "sudo npm install -g pm2"
    exit 1
fi

echo "PM2 encontrado."

# ==================================================
# Verifica se já existe processo
# ==================================================

echo
echo "Verificando processo $API no PM2..."

if sudo -u "$USUARIO" pm2 describe "$API" >/dev/null 2>&1; then
    echo
    echo "Erro: já existe um processo PM2 chamado $API."
    echo
    sudo -u "$USUARIO" pm2 describe "$API"
    exit 1
fi

# ==================================================
# NGINX
# ==================================================

echo
echo "Provisionando Nginx..."

if ! sudo provisionar-backend "$PORTA" "$API"; then
    echo
    echo "Erro: não foi possível provisionar o Nginx."
    echo "A API ainda não foi iniciada."
    exit 1
fi

echo
echo "Nginx provisionado com sucesso."

# ==================================================
# Inicia PM2
# ==================================================

echo
echo "Iniciando API com PM2..."

if ! sudo -u "$USUARIO" pm2 start npm \
    --name "$API" \
    --cwd "$PASTA" \
    -- start; then

    echo
    echo "Erro ao iniciar a API com PM2."
    echo "Restaurando configuração do Nginx..."

    exit 1
fi

echo "API iniciada."

# ==================================================
# Salva PM2
# ==================================================

echo
echo "Salvando processos do PM2..."

sudo -u "$USUARIO" pm2 save

# ==================================================
# Configura PM2 no systemd
# ==================================================

echo
echo "Configurando PM2 no systemd..."

sudo -u "$USUARIO" pm2 startup systemd \
    -u "$USUARIO" \
    --hp "$HOME_USUARIO" \
    >/tmp/pm2-startup.txt 2>&1 || true

cat /tmp/pm2-startup.txt

STARTUP_COMMAND=$(grep -E '^sudo ' /tmp/pm2-startup.txt | tail -n 1 || true)

if [ -n "$STARTUP_COMMAND" ]; then
    echo
    echo "Executando configuração do systemd..."

    eval "$STARTUP_COMMAND"
fi

# ==================================================
# Salva novamente
# ==================================================

echo
echo "Salvando processos do PM2 novamente..."

sudo -u "$USUARIO" pm2 save

# ==================================================
# Verificação
# ==================================================

echo
echo "Verificando API..."

sleep 2

sudo -u "$USUARIO" pm2 describe "$API"

echo
echo "================================="
echo " API Node.js provisionada!"
echo "================================="
echo
echo "API:    $API"
echo "Pasta:  $PASTA"
echo "Porta:  $PORTA"
echo "URL:    /$API/"
echo
echo "PM2:"
echo "  pm2 status"
echo "  pm2 logs $API"
echo "  pm2 restart $API"
echo "  pm2 stop $API"
echo
echo "Systemd:"
echo "  systemctl status pm2-$USUARIO"
