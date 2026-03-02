# WxO CLI Validation Guide — TZ1 ↔ TZ2

**Version:** 1.0.8 (Mar 1, 2026)

This guide describes how to test all CLI options and validate function between TZ1 and TZ2.

## Prerequisites

1. **Orchestrate CLI** installed and in PATH
2. **.env** with API keys (scripts look for: `watson-orchestrate-builder/.env`, `watsonx-orchestrate-devkit/.env`, or `wxo-toolkit/.env`):
   ```bash
   cp .env.example .env
   # Edit .env: add WXO_API_KEY_TZ1, WXO_API_KEY_TZ2 (and optionally WXO_URL_TZ1, WXO_URL_TZ2)
   ```
3. **TZ1 and TZ2** environments in `orchestrate env list`

## Quick Validation (Automated)

```bash
# List all test cases
./run_wxo_tests.sh --list

# Quick mode: tools export, import, validate (~2–3 min)
./run_wxo_tests.sh --quick

# Full mode: all export/import permutations, compare, replicate (~10–15 min)
./run_wxo_tests.sh --full

# Skip agent validation (faster)
./run_wxo_tests.sh --full --no-validate
```

Output: `WxO/TestRun/<datetime>/` with `test_report.txt` and `logs/`.

## Manual Validation — All Options

### 1. Interactive Menu (`wxo_exporter_importer.sh`)

```bash
./wxo_exporter_importer.sh
```

Then exercise:

| Action | Options to test |
|--------|-----------------|
| **Export** | [1] Agents, [2] Tools, [3] Flows, [4] Plugins, [5] All, [6] Connections |
| **Import** | [1] Agents, [2] Tools, [3] Flows, [4] Plugins, [5] Connections, [6–9] With deps / Folder |
| **Compare** | Compare TZ1 vs TZ2 |
| **Validate** | Invoke agents with test prompt |
| **Replicate** | Copy source → target (agents, tools, flows, connections) |
| **Danger Zone** | Delete (use with caution) |

### 2. Direct Script Calls

**Export:**
```bash
# Activate source
orchestrate env activate TZ1 --api-key "$WXO_API_KEY_TZ1"

# Export options
./export_from_wxo.sh -o WxO --env-name TZ1 --agents-only
./export_from_wxo.sh -o WxO --env-name TZ1 --tools-only
./export_from_wxo.sh -o WxO --env-name TZ1 --flows-only
./export_from_wxo.sh -o WxO --env-name TZ1 --plugins-only
./export_from_wxo.sh -o WxO --env-name TZ1 --connections-only
./export_from_wxo.sh -o WxO --env-name TZ1  # All
```

**Import:**
```bash
# Activate target
orchestrate env activate TZ2 --api-key "$WXO_API_KEY_TZ2"

EXPORT_DIR="WxO/Exports/TZ1/$(ls -1t WxO/Exports/TZ1/ | head -1)"

./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --agents-only --no-credential-prompt
./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --tools-only --no-credential-prompt
./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --flows-only --no-credential-prompt
./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --plugins-only --no-credential-prompt
./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --connections-only --no-credential-prompt
./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --all --no-credential-prompt
```

**Compare:**
```bash
./compare_wxo_systems.sh TZ1 TZ2 -o WxO/Compare/TZ1-TZ2/report.txt
```

**Validate (invoke agents):**
```bash
./import_to_wxo.sh --base-dir "$EXPORT_DIR" --env TZ2 --agents-only --no-credential-prompt --validate
```

### 3. Replicate (TZ1 → TZ2)

```bash
# Export from TZ1 to Replicate folder, then import to TZ2
orchestrate env activate TZ1 --api-key "$WXO_API_KEY_TZ1"
./export_from_wxo.sh -o WxO --env-name "TZ1_to_TZ2" --replicate --agents-only

REPL_DIR="WxO/Replicate/TZ1_to_TZ2/$(ls -1t WxO/Replicate/TZ1_to_TZ2/ | head -1)"
orchestrate env activate TZ2 --api-key "$WXO_API_KEY_TZ2"
./import_to_wxo.sh --base-dir "$REPL_DIR" --env TZ2 --all --no-credential-prompt
```

## Validation Checklist

- [ ] Export: agents, tools, flows, plugins, connections, all
- [ ] Import: agents, tools, flows, plugins, connections, all (folder)
- [ ] Compare: TZ1 vs TZ2 report
- [ ] Validate: agents respond to test prompt
- [ ] Replicate: TZ1 → TZ2 (agents with deps)
- [ ] `--if-exists skip` and `override` behave correctly

## Troubleshooting

- **"orchestrate CLI not found"** — Install: https://developer.watson-orchestrate.ibm.com/getting_started/installing
- **"No environment is active"** — Run `orchestrate env activate TZ1 --api-key <key>`
- **"jq required"** — `brew install jq` or `apt-get install jq`
- **API key errors** — Ensure `WXO_API_KEY_TZ1` and `WXO_API_KEY_TZ2` in .env or environment
- **Python tool import: "No module named 'X.X'"** — The import script auto-fixes module/package name collisions (e.g. `dad_joke_plugin/dad_joke_plugin.py`). If failures persist, rename the main `.py` to `<tool_name>_tool.py` in the export dir and re-import.
