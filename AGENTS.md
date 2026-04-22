---
title: "Agents Master"
tags: []
---

# AGENTS.md — hale-bopp-iron-dome

> Guardrail non-AI per sicurezza nel ciclo agentic.
> Guardrails e regole: vedi `.cursorrules` nello stesso repo.
> Workspace map: vedi `easyway/infra/factory-vcs.json` (SSoT repo map, branch strategy, deploy metadata).

## Identità
| Campo | Valore |
|---|---|
| Cosa | Security hooks, policy checks, preventive guardrails |
| Linguaggio | Bash, Python |
| Branch | `feature/* -> develop -> main` (target da `factory-vcs.json`) |


## Comandi rapidi
```bash
ewctl commit
./scripts/run-checks.sh
```

## Struttura
```text
scripts/         # Guard scripts
docs/            # Security documentation
```

## Regole specifiche iron-dome
| Regola | Dettaglio |
|---|---|
| Security-first | meglio blocco rumoroso che leak silenzioso |
| Auditability | output e motivazioni sempre tracciabili |

## Workflow & Connessioni
| Cosa | Dove |
|---|---|
| ADO operations (WI, PR) | → vedi `easyway-wiki/guides/agents/agent-ado-operations.md` |
| PR flusso standard | → vedi `easyway-wiki/guides/polyrepo-git-workflow.md` |
| PAT/secrets/gateway | → vedi `easyway-wiki/guides/connection-registry.md` |
| Branch strategy | → vedi `easyway-wiki/guides/branch-strategy-config.md` |
| Tool unico | `bash /c/EW/easyway/agents/scripts/connections/ado.sh` — MAI curl inline, MAI az login |


---
> Context Sync Engine | Master: `easyway-wiki/templates/agents-master.md`
> Override: `easyway-wiki/templates/repo-overrides.yml` | Sync: 2026-04-22T06:00:12Z
