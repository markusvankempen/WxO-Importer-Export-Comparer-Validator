
## Guardrails and validation

| Check | Scripts | Behavior |
|-------|---------|----------|
| orchestrate CLI | All | Exit with install URL if not found |
| jq | Main, export, compare, test | Exit if not found |
| unzip | Export | Exit if not found |
| agents/, tools/ | Import | Exit with path hint if missing |
| .env for API keys | Main, import, compare, test | Use when present; prompt otherwise |

