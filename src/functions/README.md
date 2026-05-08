# Functions auxiliares (reservado)

Diretorio reservado para HTTP triggers auxiliares fora do agent runner principal.

## Casos de uso futuros

- **Health check endpoint** (`/health`) — usado por APIM backend pool
- **Cost telemetry endpoint** (`/cost-snapshot`) — emite custo agregado por tenant via Cost Management API
- **Webhook circuit-breaker** (`/circuit-breaker`) — recebe trigger do Logic App quando spike de custo / errors detectado

## Status

Vazio na v0.1.0-init. Sera preenchido em iteracoes posteriores quando os capitulos `docs/` forem expandidos com conteudo Portal step-by-step real.
