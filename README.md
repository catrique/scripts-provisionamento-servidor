# Scripts de provisionamento de servidor

Scripts Shell para publicar frontends, aplicações Python/Flask e APIs Node.js em servidores Linux com Nginx e PM2.

## Scripts

| Script | Finalidade |
| --- | --- |
| `subir-frontend.sh` | Publica um frontend estático no Nginx. |
| `subir-app-python.sh` | Publica uma aplicação Python com PM2. |
| `subir-app-flask.sh` | Publica uma aplicação Flask com PM2. |
| `subir-api-python.sh` | Publica uma API Python/ASGI, como FastAPI, com Uvicorn e PM2. |
| `subir-api-node.sh` | Publica uma API Node.js com PM2. |
| `provisionar-backend.sh` | Cria uma rota de proxy no Nginx para um backend local. |

## Antes de usar

1. Ajuste no início de cada script os caminhos, o usuário e o IP conforme o servidor.
2. Confira se o Nginx, o PM2 e a tecnologia da aplicação já estão instalados.
3. Execute com `sudo`.

Exemplo:

```bash
sudo ./subir-api-node.sh minha-api 8001
```

> Revise os scripts antes de executar em produção. Eles alteram configurações do Nginx e processos do PM2.

## Usar sem `.sh`

Os scripts podem ser movidos para `/usr/local/bin` e renomeados para serem chamados de qualquer pasta, sem a extensão `.sh`:

```bash
chmod +x subir-api-node.sh
sudo mv subir-api-node.sh /usr/local/bin/subir-api-node
```

Depois, execute normalmente:

```bash
sudo subir-api-node minha-api 8001
```

Repita o mesmo processo para os demais scripts.
