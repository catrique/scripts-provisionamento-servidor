#!/bin/bash

set -e

BASE="/caminho/para/diretorio/base"
USUARIO="seu_usuario"
HOME_USUARIO="/home/seu_usuario"
IP="IP onde o serviço será executado"

if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <pasta> <porta>"
    echo
    echo "Exemplo:"
    echo "sudo $0 atos 5017"
    exit 1
fi

APP="$1"
PORTA="$2"
PASTA="$BASE/$APP"

echo "================================="
echo " Provisionando aplicação Flask"
echo "================================="
echo "Aplicação: $APP"
echo "Pasta:     $PASTA"
echo "Porta:     $PORTA"
echo

# ==================================================
# Validação da pasta
# ==================================================

echo "Verificando pasta..."

if [ ! -d "$PASTA" ]; then
    echo
    echo "Erro: a pasta não existe:"
    echo "$PASTA"
    exit 1
fi

echo "Pasta encontrada."

# ==================================================
# Validação do ambiente virtual
# ==================================================

echo
echo "Verificando ambiente virtual..."

if [ ! -x "$PASTA/.venv/bin/flask" ]; then
    echo
    echo "Erro: Flask não encontrado no ambiente virtual:"
    echo "$PASTA/.venv/bin/flask"
    echo
    echo "Crie o ambiente virtual e instale as dependências antes:"
    echo
    echo "cd $PASTA"
    echo "python3 -m venv .venv"
    echo ".venv/bin/pip install -r requirements.txt"
    exit 1
fi

echo "Flask encontrado."

# ==================================================
# Validação do app.py
# ==================================================

echo
echo "Verificando arquivo principal..."

if [ -f "$PASTA/app.py" ]; then
    APP_MODULE="app"
    ARQUIVO_PRINCIPAL="app.py"
elif [ -f "$PASTA/server.py" ]; then
    APP_MODULE="server"
    ARQUIVO_PRINCIPAL="server.py"
elif [ -f "$PASTA/main.py" ]; then
    APP_MODULE="main"
    ARQUIVO_PRINCIPAL="main.py"
else
    echo
    echo "Erro: não foi encontrado app.py , server.py nem main.py."
    echo
    echo "A aplicação precisa possuir um destes arquivos:"
    echo "  app.py"
    echo "  server.py"
    echo "  main.py"
    exit 1
fi

echo "Arquivo principal encontrado: $ARQUIVO_PRINCIPAL"
echo "Módulo Flask: $APP_MODULE"
# ==================================================
# Verificação da porta
# ==================================================

echo
echo "Verificando porta $PORTA..."

if sudo lsof -i :"$PORTA" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo
    echo "Erro: a porta $PORTA já está em uso."
    echo
    sudo lsof -i :"$PORTA" -sTCP:LISTEN
    exit 1
fi

echo "Porta $PORTA está disponível."

# ==================================================
# Verificação do PM2
# ==================================================

echo
echo "Verificando PM2..."

if ! sudo -u "$USUARIO" command -v pm2 >/dev/null 2>&1; then
    echo
    echo "Erro: PM2 não está instalado para o usuário $USUARIO."
    echo
    echo "Instale com:"
    echo "sudo npm install -g pm2"
    exit 1
fi

echo "PM2 encontrado."

# ==================================================
# Verificação de processo existente
# ==================================================

echo
echo "Verificando processo $APP no PM2..."

if sudo -u "$USUARIO" pm2 describe "$APP" >/dev/null 2>&1; then
    echo
    echo "Erro: já existe um processo PM2 chamado $APP."
    echo
    sudo -u "$USUARIO" pm2 describe "$APP"
    exit 1
fi

echo "Nenhum processo PM2 com esse nome encontrado."

# ==================================================
# Provisionamento do Nginx
# ==================================================

echo
echo "Provisionando Nginx..."

if ! sudo provisionar-backend "$PORTA" "$APP"; then
    echo
    echo "Erro: não foi possível provisionar o Nginx."
    echo "A aplicação não foi iniciada."
    exit 1
fi

echo
echo "Nginx provisionado com sucesso."

# ==================================================
# Iniciar Flask com PM2
# ==================================================

echo
echo "Iniciando aplicação Flask com PM2..."

if ! sudo -u "$USUARIO" pm2 start "$PASTA/.venv/bin/flask" \
    --name "$APP" \
    --cwd "$PASTA" \
    --interpreter none \
    -- \
    --app app \
    run \
    --host "$IP" \ 
    --port "$PORTA"; then

    echo
    echo "Erro ao iniciar a aplicação Flask."
    echo
    echo "O provisionamento do Nginx foi realizado,"
    echo "mas a aplicação não foi iniciada."
    exit 1
fi

echo
echo "Aplicação Flask iniciada."

# ==================================================
# Salvar processos PM2
# ==================================================

echo
echo "Salvando processos do PM2..."

sudo -u "$USUARIO" pm2 save

# ==================================================
# Verificar PM2 systemd
# ==================================================

echo
echo "Verificando inicialização automática do PM2..."

if systemctl is-enabled pm2-"$USUARIO" >/dev/null 2>&1; then
    echo "PM2 já está configurado para iniciar com o sistema."
else
    echo
    echo "PM2 ainda não está configurado no systemd."
    echo "Configurando..."

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
fi

# ==================================================
# Salvar novamente
# ==================================================

echo
echo "Salvando processos do PM2 novamente..."

sudo -u "$USUARIO" pm2 save

# ==================================================
# Verificação final
# ==================================================

echo
echo "Verificando aplicação..."

sleep 2

sudo -u "$USUARIO" pm2 describe "$APP"

# ==================================================
# Final
# ==================================================

echo
echo "================================="
echo " Flask provisionado com sucesso!"
echo "================================="
echo
echo "Aplicação: $APP"
echo "Pasta:     $PASTA"
echo "Porta:     $PORTA"
echo "URL:       /$APP/"
echo
echo "PM2:"
echo "  pm2 status"
echo "  pm2 logs $APP"
echo "  pm2 restart $APP"
echo "  pm2 stop $APP"
echo
echo "Systemd:"
echo "  systemctl status pm2-$USUARIO"
echo
