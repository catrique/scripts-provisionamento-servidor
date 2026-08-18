#!/bin/bash

set -e

BASE="/caminho/para/diretorio/base"
USUARIO="seu_usuario"
HOME_USUARIO="/home/seu_usuario"

if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <pasta> <porta>"
    echo
    echo "Exemplo:"
    echo "sudo $0 atividades-semanais 8010"
    exit 1
fi

APP="$1"
PORTA="$2"
PASTA="$BASE/$APP"

echo "================================="
echo " Provisionando aplicação Python"
echo "================================="
echo "Aplicação: $APP"
echo "Pasta:     $PASTA"
echo "Porta:     $PORTA"
echo

# ==================================================
# Validações
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
# Arquivo principal
# ==================================================

echo
echo "Procurando arquivo principal..."

if [ -f "$PASTA/server.py" ]; then
    ARQUIVO="server.py"
elif [ -f "$PASTA/app.py" ]; then
    ARQUIVO="app.py"
elif [ -f "$PASTA/main.py" ]; then
    ARQUIVO="main.py"
else
    echo
    echo "Erro: não foi encontrado um arquivo Python principal."
    echo
    echo "Arquivos aceitos:"
    echo "  server.py"
    echo "  app.py"
    echo "  main.py"
    exit 1
fi

echo "Arquivo encontrado: $ARQUIVO"

# ==================================================
# Ambiente virtual
# ==================================================

echo
echo "Verificando ambiente virtual..."

if [ ! -x "$PASTA/.venv/bin/python" ]; then

    echo "Ambiente virtual não encontrado."
    echo "Criando .venv..."

    sudo -u "$USUARIO" python3 -m venv "$PASTA/.venv"

    echo "Ambiente virtual criado."

else

    echo "Ambiente virtual encontrado."

fi

PYTHON="$PASTA/.venv/bin/python"
PIP="$PASTA/.venv/bin/pip"

# ==================================================
# Requirements
# ==================================================

echo
echo "Verificando requirements.txt..."

if [ -f "$PASTA/requirements.txt" ]; then

    echo "requirements.txt encontrado."
    echo
    echo "Instalando dependências..."

    sudo -u "$USUARIO" "$PIP" install -r "$PASTA/requirements.txt"

    echo
    echo "Dependências instaladas."

else

    echo "requirements.txt não encontrado."
    echo "Nenhuma dependência externa será instalada."

fi

# ==================================================
# Verifica porta
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
# Verifica PM2
# ==================================================

echo
echo "Verificando PM2..."

if ! command -v pm2 >/dev/null 2>&1; then

    echo
    echo "Erro: PM2 não está instalado."
    echo
    echo "Instale com:"
    echo "sudo npm install -g pm2"

    exit 1
fi

echo "PM2 encontrado."

# ==================================================
# Verifica processo existente
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

# ==================================================
# NGINX
# ==================================================

echo
echo "Provisionando Nginx..."

if ! sudo provisionar-backend "$PORTA" "$APP"; then

    echo
    echo "Erro: não foi possível provisionar o Nginx."
    echo "A aplicação ainda não foi iniciada."

    exit 1
fi

echo
echo "Nginx provisionado com sucesso."

# ==================================================
# PM2
# ==================================================

echo
echo "Iniciando aplicação com PM2..."

if ! sudo -u "$USUARIO" env \
    PORT="$PORTA" \
    pm2 start "$PYTHON" \
    --name "$APP" \
    --cwd "$PASTA" \
    --interpreter none \
    -- "$ARQUIVO"; then

    echo
    echo "Erro ao iniciar a aplicação com PM2."
    exit 1
fi

echo
echo "Aplicação iniciada."

# ==================================================
# Salva PM2
# ==================================================

echo
echo "Salvando processos do PM2..."

sudo -u "$USUARIO" pm2 save --force

# ==================================================
# Verifica serviço PM2
# ==================================================

echo
echo "Verificando serviço pm2-govdig..."

if systemctl is-enabled pm2-govdig >/dev/null 2>&1; then

    echo "pm2-govdig está habilitado."

else

    echo
    echo "Aviso: pm2-govdig não está habilitado."
    echo "O processo continuará funcionando, mas o PM2 pode não iniciar automaticamente após reboot."

fi

# ==================================================
# Verificação
# ==================================================

echo
echo "Aguardando aplicação iniciar..."

sleep 2

echo
echo "Status da aplicação:"

sudo -u "$USUARIO" pm2 describe "$APP"

echo
echo "================================="
echo " Aplicação Python provisionada!"
echo "================================="
echo
echo "Aplicação: $APP"
echo "Pasta:     $PASTA"
echo "Arquivo:   $ARQUIVO"
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
echo "  systemctl status pm2-govdig"
echo
