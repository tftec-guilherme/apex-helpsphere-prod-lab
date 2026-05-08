# Security Policy

## Reporting a Vulnerability

Se você descobriu uma vulnerabilidade de segurança neste repo (lab pedagógico), por favor **NÃO abra issue pública**. Em vez disso:

1. Envie email para: **guilherme.campos@tftec.com.br**
2. Inclua:
   - Descrição da vulnerabilidade
   - Passos para reproduzir
   - Impacto potencial
   - Sugestão de correção (se houver)

## Responsible Disclosure

- Responderemos em até **5 dias úteis**
- Coordenaremos disclosure após correção cravada
- Crédito público dado se você desejar

## Escopo

Este repo é **lab pedagógico** — não há produção real. Vulnerabilidades em escopo:

- Secrets vazados em commits / docs
- Bicep com configurações inseguras (ex: público sem auth)
- Workflows GitHub Actions com `pull_request_target` mal configurado
- Snippets Python com SQL injection / XSS
- Defaults de parâmetros que expõem recursos publicamente

## Fora de escopo

- Vulnerabilidades em **dependências third-party** (Azure SDK, Functions runtime) — reporte upstream
- Vulnerabilidades **teóricas** sem PoC reproduzível
- "Best practices" que não são exploits reais (use issue normal pra sugerir hardening)

---

**Maintainer:** Prof. Guilherme Campos
**Email security:** guilherme.campos@tftec.com.br
