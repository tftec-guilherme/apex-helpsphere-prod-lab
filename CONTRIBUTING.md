# Contributing

Este repo é um **lab pedagógico** da Disciplina 06 (Pós-Graduação em Arquitetura Cloud Azure | TFTEC + Anhanguera). Não é um projeto open-source ativo, mas correções e melhorias são bem-vindas.

## Como contribuir

1. Faça **fork** do repo
2. Crie branch: `git checkout -b feat/minha-melhoria`
3. Commits no padrão **Conventional Commits**:
   - `feat:` — nova feature
   - `fix:` — bug fix
   - `docs:` — só documentação
   - `chore:` — manutenção / refactor sem mudança funcional
   - `ci:` — workflows GitHub Actions
4. Abra **Pull Request** descrevendo:
   - Problema resolvido (ou melhoria)
   - Como testou (Bicep what-if + run de workflow ci)
   - Impacto pedagógico (afeta capítulo X de `docs/`?)

## Code style

- **Bicep**: rode `az bicep lint` antes de commitar
- **Python**: rode `ruff check src/ eval/` antes de commitar
- **YAML workflows**: rode `actionlint` se possível

## Reportar bugs

Use [GitHub Issues](https://github.com/tftec-guilherme/apex-helpsphere-prod-lab/issues) com:
- Versão do Az CLI / Bicep
- Output completo do erro
- Comando exato que reproduziu

## Disclaimer

Este repo segue padrões da disciplina e **não aceita PRs que alterem disclaimers HIGH** (R4 APIM, R6 ABAC, Free Trial) sem discussão prévia com o professor.

---

Obrigado por contribuir! 🎓
