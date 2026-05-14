# Appendix: Surpresas Pedagógicas — apex-helpsphere-prod-lab

Catálogo de surpresas, armadilhas e gotchas descobertos durante construção e execução do Lab Avançado D06. Inspirado em [`apex-helpsphere/APPENDIX-SURPRESAS.md`](https://github.com/tftec-guilherme/apex-helpsphere/blob/main/APPENDIX-SURPRESAS.md) (35 surpresas catalogadas na fundação SaaS).

Cada entry: contexto, sintoma, causa raiz, fix/workaround, lição.

---

## #1 — ABAC condition em conta VSE pessoal bloqueia fork-by-student CI

**Categoria:** Identity / Authorization
**Severidade:** HIGH
**Capítulo afetado:** Originalmente cap 05 (GitHub Actions), agora removido (D3)

**Contexto:** Conta Visual Studio Enterprise pessoal vinculada a `live.com` tem ABAC condition no role assignment que filtra principal type. Federated Service Principal de fork de aluno (diferente do principal original) falha auth.

**Sintoma:** `azd up` ou `az deployment group create` via GitHub Actions retorna `AuthFailed` mesmo com OIDC trust + federated credentials configurados corretamente.

**Causa raiz:** ABAC condition `request:Subject != null AND principal:PrincipalType == 'ServicePrincipal'` (ou similar) presente no role assignment do RG/subscription bloqueia principals que não batem com pattern original.

**Fix definitivo:** Não há fix automático para conta VSE pessoal — requer override manual do ABAC condition pelo owner da subscription.

**Workaround adotado (D3 Story 06.19):** Remover `.github/workflows/` desta versão. Lab vira 100% Portal+CLI manual. Aluno usa `az login` próprio + role Contributor em `rg-lab-avancado` próprio.

**Lição:** Testar ABAC ANTES de propor federated SP. Memória: `feedback_abac_condition_blocks_fork_by_student.md`.

---

## #2 — Audit sample-by-sample subestima escopo em 60-70%

**Categoria:** Methodology / Process
**Severidade:** MEDIUM
**Capítulo afetado:** Story 06.16 (PowerShell refactor)

**Contexto:** Audit inicial da Story 06.16 reportou 21 findings de bash residual nos 10 caps `docs/`. Re-audit 100%-coverage (Story 06.16 dispatch) detectou escopo real: 26 fences bash + 276 line continuations + 7 `VAR=$()` + 2 `export VAR=$()` = **~6x maior**.

**Sintoma:** Plan Wave 4 v1 dimensionou refactor para 1 subagente; reality required 5 subagentes paralelos em 2 ondas.

**Causa raiz:** Audit anterior fez sampling (3-4 arquivos) ao invés de grep agnóstico em 100% dos arquivos.

**Fix:** Sempre fazer audit 100%-coverage com greps agnósticos antes de listar findings:

```powershell
# Pattern correto (agnóstico)
Select-String -Path docs\*.md -Pattern '^```bash' | Measure-Object
Select-String -Path docs\*.md -Pattern ' \\$' | Measure-Object  # line cont bash
Select-String -Path docs\*.md -Pattern '^[A-Z_]+=\$\(' | Measure-Object  # VAR=$()
Select-String -Path docs\*.md -Pattern '^export [A-Z_]+=' | Measure-Object
```

**Lição:** Sampling é heurístico, não auditoria. Memória: `feedback_audit_100pct_coverage.md`.

---

## #3 — APIM Developer não tem auto-pause (R$ 250/mês ligado)

**Categoria:** Cost / FinOps
**Severidade:** HIGH
**Capítulo afetado:** `docs/06-apim-gateway-policies.md` + `docs/10-cleanup.md`

**Contexto:** APIM Developer tier é production-grade entry (suporta policies completas — JWT, rate-limit, CORS) mas não tem mecanismo de auto-pause como Consumption.

**Sintoma:** Aluno provisiona APIM em sexta-feira, esquece no fim de semana, segunda-feira já queimou R$ 30+ do orçamento.

**Causa raiz:** Tier Developer cobra por hora ligado, independente de tráfego. Diferente de Consumption (pay-per-call).

**Fix/workaround:**
1. **Cleanup obrigatório no fim do lab** — `az group delete --name rg-lab-avancado --yes --no-wait`
2. **Alternativa:** `param apimSku string = 'Consumption'` em `infra/envs/dev.parameters.json` — algumas policies podem não funcionar (ver `docs/06`)
3. **Comprometa-se:** rodar lab em 3-5 dias úteis seguidos, não estender por 2 semanas

**Lição:** Disclaimer R4 em `PARA-O-ALUNO.md` documenta isso explicitamente. Custo total se demorar 1 mês: ~R$ 280 (vs ~R$ 50 se cleanup em 3-5 dias).

---

## #4 — Bicep `targetScope='subscription'` cria RG duplicado quando docs/02 também cria

**Categoria:** IaC / Bicep
**Severidade:** CRITICAL
**Capítulo afetado:** `infra/main.bicep` + `docs/02-rg-github-setup.md`

**Contexto:** Versões v0.1.0/v0.2.0 do prod-lab tinham `targetScope='subscription'` no Bicep, que criava o RG automaticamente. Mas `docs/02` ensinava criar `rg-lab-avancado` manualmente no Portal antes.

**Sintoma:** Bicep cria `rg-helpsphere-ia-prod-dev` enquanto docs/02 criou `rg-lab-avancado` — 2 RGs, deployment falha ou cria recursos em RG errado.

**Causa raiz:** Mismatch entre fontes (Bicep + docs + workflows hardcoded). Audit Story 06.19 (`ab6651add368bee88`) detectou.

**Fix definitivo (D2 Story 06.19):** Mudar para `targetScope='resourceGroup'`. Aluno cria RG manualmente, Bicep só popula. Removidos params `rgName` e `location` (substituídos por `resourceGroup().name` e `resourceGroup().location`).

**Lição:** 1 fonte de verdade para infra. Memória: `feedback_confirmar_arquitetura_antes_propor.md`.

---

## #5 — `bash` heredoc fundamentalmente incompatível com PowerShell

**Categoria:** Shell / Refactor
**Severidade:** MEDIUM
**Capítulo afetado:** `docs/02-rg-github-setup.md:199` (única exceção proposital)

**Contexto:** Story 06.16 converteu 26 fences `bash` → `powershell` nos 10 caps. Mas heredoc bash (`cat > file <<EOF ... EOF`) não tem equivalente PowerShell idêntico — here-string `@'...'@` é o mais próximo mas tem sintaxe diferente (fechamento na coluna 0 obrigatório).

**Sintoma:** Conversão direta de heredoc falha (parse error).

**Causa raiz:** Heredoc bash usa shell redirection (`> file <<EOF`), PowerShell here-string usa atribuição (`$content = @'...'@; Set-Content file $content`).

**Fix adotado:** Documentar alternativa explícita inline com nota "Alternativa Linux/Mac/WSL (bash)" — única exceção bash mantida propositalmente em `docs/02:199`.

**Lição:** Refactor não é sintaxe textual, é semântica. Documentar exceções inline com rationale.

---

## #6 — `string slicing` PowerShell ≠ Bash `${VAR:0:8}`

**Categoria:** Shell / String manipulation
**Severidade:** LOW
**Capítulo afetado:** `docs/07-content-safety-app-insights.md`

**Contexto:** Story 06.16 detectou 3 fixes CRÍTICOS em `docs/07` linhas 332/346/347 envolvendo `FUNC_NAME=$()`, `APIM_URL=$()`, `SUB_KEY=$()` — mas ALÉM disso, sintaxe `${VAR:0:8}` (string slicing bash) também aparecia.

**Sintoma:** PowerShell falha em parsing `${VAR:0:8}` (interpreta como expressão hash).

**Causa raiz:** Bash `${VAR:0:8}` = substring 0-7 chars. PowerShell equivalente: `$VAR.Substring(0, 8)` (método .NET).

**Fix:** Conversão `${VAR:0:8}` → `$VAR.Substring(0, 8)` no contexto correto (após `$VAR` ser atribuído via `$VAR = az ...`).

**Lição:** Refactor PowerShell-first exige conhecimento de métodos .NET para strings.

---

## #7 — Wave 4 plan v1 obsoleto mid-flight (escopo 100% reescrito)

**Categoria:** Planning / Process
**Severidade:** MEDIUM
**Capítulo afetado:** Story 06.21+ (Wave 4 autopilot)

**Contexto:** Plan Wave 4 v1 (2026-05-09) presumia caps em outline `v0.1.0-init`. Audit pré-execução em 2026-05-11 revelou que Stories 06.18 (agente-lab) e 06.19 (prod-lab) JÁ haviam expandido todos os 21 caps para `v0.2.0-portal` / `v0.3.0-cli-manual` em 2026-05-10.

**Sintoma:** Plan diz "expandir 21 caps de outline para production-grade" — reality "polish 21 caps que já estão production-grade".

**Causa raiz:** Plan tinha >7 dias. Stories executadas nesse intervalo mudaram baseline. Plan vs reality drift.

**Fix:** Reescopar Wave 4 para **polish dirigido + AMBs cirúrgicas**. AMB-5 SUPERSEDED (manter split 04a/04b já implementado).

**Lição:** Sempre fazer audit de estado real ANTES de dispatch de plan multi-arquivo, especialmente se plan tem >7 dias. Memória: `feedback_plan_vs_reality_audit.md`.

---

## #8 — `live.com` email em commits propaga sem awareness do prof

**Categoria:** Privacy / Git
**Severidade:** LOW
**Capítulo afetado:** Todos (configuração git global)

**Contexto:** Prof preferia `guilherme.prux@live.com` (pessoal) sobre `guilherme.campos@tftec.com.br` (corporativo) em novos commits/configs.

**Sintoma:** Commits em repos públicos podem expor email corporativo sem awareness do prof.

**Causa raiz:** `git config user.email` global ainda apontava para corporativo em muitos repos.

**Fix:** Aplicar `git config user.email guilherme.prux@live.com` no escopo local de cada repo conforme necessário (não aplicado globalmente — apenas em `apex-rag-lab` em 2026-05-09, expansão caso-a-caso).

**Lição:** Email config é decisão por repo. Memória: prefs do prof.

---

## Como adicionar uma surpresa

1. Encontre uma armadilha nova durante execução
2. Pegue categoria (Identity / Cost / IaC / Shell / Planning / etc.)
3. Documente: Contexto · Sintoma · Causa raiz · Fix/Workaround · Lição
4. PR com 1 entry por commit (não bundle)

---

## Cross-references

- **Gold standard:** [`apex-helpsphere/APPENDIX-SURPRESAS.md`](https://github.com/tftec-guilherme/apex-helpsphere/blob/main/APPENDIX-SURPRESAS.md) — 35 surpresas na fundação SaaS
- **Decision log:** [`DECISION-LOG.md`](./DECISION-LOG.md) — decisões arquiteturais cravadas
- **Sibling:** [`apex-helpsphere-agente-lab`](https://github.com/tftec-guilherme/apex-helpsphere-agente-lab) — companion Lab Final

---

**Última revisão:** 2026-05-14 (Story 06.22 — 8 surpresas iniciais consolidadas pós Wave 4)
