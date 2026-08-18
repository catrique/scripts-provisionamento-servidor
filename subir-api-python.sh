#!/usr/bin/env bash

set -euo pipefail

BASE="/caminho/para/diretorio/base"
USUARIO="seu_usuario"
HOME_USUARIO="/home/seu_usuario"
IP="IP onde o serviço será executado"

uso() {
    echo "Uso: $0 <pasta> <porta> [modulo:aplicacao]"
    echo
    echo "Exemplo:"
    echo "sudo $0 api-exemplo 8001"
    echo
    echo "O ponto de entrada padrão é main:app quando existe main.py."
}

erro() {
    echo
    echo "Erro: $1"
    exit 1
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    uso
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    erro "execute o script com sudo."
fi

API="$1"
PORTA="$2"
ENTRADA="${3:-}"
PASTA="$BASE/$API"

if ! [[ "$API" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    erro "o nome da pasta deve usar apenas letras, números, ponto, hífen e sublinhado."
fi

if ! [[ "$PORTA" =~ ^[0-9]+$ ]] || (( 10#$PORTA < 1 || 10#$PORTA > 65535 )); then
    erro "a porta deve ser um número entre 1 e 65535."
fi

PORTA="$((10#$PORTA))"

echo "================================="
echo " Provisionando API Python (Uvicorn)"
echo "================================="
echo "API:    $API"
echo "Pasta:  $PASTA"
echo "Porta:  $PORTA"
echo

echo "Verificando pasta..."

if [ ! -d "$PASTA" ]; then
    erro "a pasta não existe: $PASTA"
fi

echo "Pasta encontrada."

echo
echo "Verificando requirements.txt..."

if [ ! -f "$PASTA/requirements.txt" ]; then
    erro "requirements.txt não encontrado: $PASTA/requirements.txt"
fi

echo "requirements.txt encontrado."

if [ -z "$ENTRADA" ]; then
    if [ -f "$PASTA/app/main.py" ]; then
        ENTRADA="app.main:app"
    elif [ -f "$PASTA/main.py" ]; then
        ENTRADA="main:app"
    elif [ -f "$PASTA/app.py" ]; then
        ENTRADA="app:app"
    elif [ -f "$PASTA/server.py" ]; then
        ENTRADA="server:app"
    else
        erro "não foi encontrado app/main.py, main.py, app.py nem server.py. Informe o ponto de entrada como terceiro argumento, por exemplo: app.main:app"
    fi
fi

if ! [[ "$ENTRADA" =~ ^[A-Za-z_][A-Za-z0-9_.]*:[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    erro "o ponto de entrada deve estar no formato modulo:aplicacao, por exemplo main:app."
fi

MODULO="${ENTRADA%%:*}"
ARQUIVO_MODULO="$PASTA/${MODULO//./\/}.py"

if [ ! -f "$ARQUIVO_MODULO" ]; then
    erro "o módulo informado não foi encontrado: $ARQUIVO_MODULO"
fi

echo
echo "Ponto de entrada: $ENTRADA"

echo
echo "Verificando Python..."

if ! command -v python3 >/dev/null 2>&1; then
    erro "python3 não está instalado."
fi

echo "Python encontrado."

echo
echo "Verificando porta $PORTA..."

if ! command -v lsof >/dev/null 2>&1; then
    erro "lsof não está instalado."
fi

if lsof -i :"$PORTA" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo
    echo "Processo utilizando a porta:"
    lsof -i :"$PORTA" -sTCP:LISTEN
    erro "a porta $PORTA já está em uso."
fi

echo "Porta $PORTA está disponível."

echo
echo "Verificando PM2..."

PM2_BIN="$(sudo -H -u "$USUARIO" bash -lc 'command -v pm2' 2>/dev/null || true)"

if [ -z "$PM2_BIN" ]; then
    erro "PM2 não está instalado para o usuário $USUARIO. Instale com: sudo npm install -g pm2"
fi

echo "PM2 encontrado."

echo
echo "Verificando processo $API no PM2..."

if sudo -H -u "$USUARIO" "$PM2_BIN" describe "$API" >/dev/null 2>&1; then
    sudo -H -u "$USUARIO" "$PM2_BIN" describe "$API"
    erro "já existe um processo PM2 chamado $API."
fi

echo "Nenhum processo PM2 com esse nome foi encontrado."

echo
echo "Criando e ativando o ambiente virtual..."

cd "$PASTA"

PYTHON="$PASTA/.venv/bin/python3"

if ! sudo -H -u "$USUARIO" test -x "$PYTHON"; then
    sudo -H -u "$USUARIO" python3 -m venv "$PASTA/.venv"
fi

if [ ! -x "$PYTHON" ]; then
    erro "o ambiente virtual foi criado, mas o interpretador não foi encontrado: $PYTHON"
fi

sudo -H -u "$USUARIO" bash -s -- "$PASTA" "$PYTHON" <<'BASH'
set -euo pipefail

PASTA="$1"
PYTHON="$2"

cd "$PASTA"

# shellcheck disable=SC1091
source .venv/bin/activate
"$PYTHON" -m pip install -r requirements.txt
BASH

if ! sudo -H -u "$USUARIO" "$PYTHON" -c 'import uvicorn' >/dev/null 2>&1; then
    erro "uvicorn não foi instalado. Inclua 'uvicorn' no requirements.txt."
fi

echo "Ambiente virtual ativado e dependências instaladas."

echo
echo "Provisionando Nginx..."

if ! command -v provisionar-backend >/dev/null 2>&1; then
    erro "o comando provisionar-backend não está instalado."
fi

if ! provisionar-backend "$PORTA" "$API"; then
    erro "não foi possível provisionar o Nginx. A API não foi iniciada."
fi

echo "Nginx provisionado com sucesso."

echo
echo "Iniciando API com PM2..."

if ! sudo -H -u "$USUARIO" "$PM2_BIN" start "$PYTHON" \
    --name "$API" \
    --cwd "$PASTA" \
    --interpreter none \
    -- \
    -m uvicorn "$ENTRADA" \
    --host "$IP" \
    --port "$PORTA" \
    --root-path "/$API" \
    --proxy-headers \
    --forwarded-allow-ips "$IP"; then
    erro "não foi possível iniciar a API com PM2."
fi

echo "API iniciada."

echo
echo "Aguardando a API iniciar..."

API_INICIOU=false

for _ in {1..10}; do
    if lsof -i :"$PORTA" -sTCP:LISTEN -t >/dev/null 2>&1; then
        API_INICIOU=true
        break
    fi

    sleep 1
done

if [ "$API_INICIOU" != true ]; then
    sudo -H -u "$USUARIO" "$PM2_BIN" logs "$API" --lines 30 --nostream || true
    sudo -H -u "$USUARIO" "$PM2_BIN" delete "$API" || true
    erro "a API não ficou escutando na porta $PORTA. O processo PM2 foi removido."
fi

echo "API está escutando na porta $PORTA."

echo
echo "Salvando processos do PM2..."
sudo -H -u "$USUARIO" "$PM2_BIN" save

echo
echo "Verificando inicialização automática do PM2..."

if systemctl is-enabled "pm2-$USUARIO" >/dev/null 2>&1; then
    echo "pm2-$USUARIO está habilitado."
else
    echo "Configurando pm2-$USUARIO no systemd..."
    "$PM2_BIN" startup systemd -u "$USUARIO" --hp "$HOME_USUARIO"
fi

echo
echo "Status da API:"
sudo -H -u "$USUARIO" "$PM2_BIN" describe "$API"

echo
echo "================================="
echo " API Python provisionada!"
echo "================================="
echo
echo "API:     $API"
echo "Pasta:   $PASTA"
echo "Entrada: $ENTRADA"
echo "Porta:   $PORTA"
echo "URL:     /$API/"
echo
echo "PM2:"
echo "  sudo -u $USUARIO pm2 status"
echo "  sudo -u $USUARIO pm2 logs $API"
echo "  sudo -u $USUARIO pm2 restart $API"
echo "  sudo -u $USUARIO pm2 stop $API"
