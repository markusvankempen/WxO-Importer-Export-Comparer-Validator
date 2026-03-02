# WxO Importer/Export Scripts — VS Code Extension Integration

This document describes how to integrate the WxO Importer/Export/Comparer/Validator shell scripts with the watsonx Orchestrate VS Code extension, including moving the interaction into webviews.

**Implemented:** A **standalone** extension lives in `vscode-extension/`. It is independent of wxo-builder. Open `internal/WxOImporterAndExporter` as workspace, run "WxO Importer/Exporter" from the Command Palette, or install the extension from the built `.vsix`.

---

## Overview

The **WxO ImporterAndExport** scripts (`wxo_exporter_importer.sh`, `export_from_wxo.sh`, `import_to_wxo.sh`, `compare_wxo_systems.sh`) use the `orchestrate` CLI to move, compare, and validate Watson Orchestrate resources. The **watsonx-orchestrate-devkit** VS Code extension currently uses the REST API for sync/export/import (via `syncImportExport.ts`).

**Goal:** Allow the extension to drive the shell scripts from a webview UI, giving users a richer experience without leaving VS Code.

---

## Current Architecture

| Component | Technology | Location |
|-----------|------------|----------|
| WxO scripts | Bash, orchestrate CLI | `internal/WxO ImporterAndExport/` |
| VS Code extension | TypeScript, REST API | `watsonx-orchestrate-devkit/packages/vscode-extension/` |
| SyncPanel | Webview + REST | `src/panels/SyncPanel.ts`, `sync/syncImportExport.ts` |

The scripts support **non-interactive CLI arguments** — no prompts when the right flags are passed:

```bash
# Export
./export_from_wxo.sh --env-name TZ1 --agents-only -o /path/to/WxO
./export_from_wxo.sh --env-name TZ1 --flows-only --tool "FlowA,FlowB"

# Import
./import_to_wxo.sh --base-dir /path/to/export --env TZ2 --no-credential-prompt --if-exists override --report-dir /path/to/report

# Compare
./compare_wxo_systems.sh ENV1 ENV2 -o report.txt
```

---

## Integration Options

### 1. Terminal (simplest)

Run the script in the integrated terminal. User sees output directly.

```typescript
const term = vscode.window.createTerminal({ name: 'WxO Export' });
term.sendText(`cd "${scriptDir}" && ./export_from_wxo.sh --env-name TZ1 --agents-only`);
term.show();
```

**Pros:** Minimal code, user can interrupt.  
**Cons:** No progress UI, no parsing of results.

### 2. Background process + Output channel

Spawn the script and stream stdout/stderr to an Output channel.

```typescript
import { spawn } from 'child_process';
const proc = spawn('bash', [scriptPath, '--env-name', env, '--agents-only'], { cwd: scriptDir });
const channel = vscode.window.createOutputChannel('WxO Scripts');
proc.stdout.on('data', d => channel.append(d.toString()));
proc.stderr.on('data', d => channel.append(d.toString()));
proc.on('close', code => { /* show notification, parse report */ });
```

**Pros:** Can parse output, show summary.  
**Cons:** More code, parsing may be brittle.

### 3. Webview-driven UI (recommended)

Build a webview panel with forms (environment, what to export, filters). User selects options, clicks Run; extension spawns the script with built args and streams progress/results back to the webview.

**Pros:** Richer UX, consistent with SyncPanel, can show live log and parsed reports.  
**Cons:** More implementation work.

---

## Webview Integration

### Existing pattern: SyncPanel

`SyncPanel` already uses this flow:

1. Webview shows forms (Source/Target config, Export/Import buttons).
2. User actions → `webview.postMessage({ command: 'export', content: {...} })`.
3. Extension handler receives and processes (currently via REST API).
4. Extension sends updates: `webview.postMessage({ command: 'operationStatus', message: '...' })`.

For script integration, handlers would invoke the shell scripts instead of REST calls.

### Message flow (webview ↔ extension)

```
Webview                                    Extension
   |                                            |
   |  postMessage({ command: 'runExport', content: { env: 'TZ1', what: 'agents-only' } })
   |  -------------------------------------------------------------------------->  |
   |                                                                               | spawn export_from_wxo.sh
   |                                                                               | capture stdout
   |  <---------------------------------------  postMessage({ command: 'progress', line: '...' })
   |                                            |
   |  (webview appends to log div)               |
   |                                             |
   |  <---------------------------------------  postMessage({ command: 'done', reportPath: '...' })
   |                                             |
   |  (show success, link to report)            |
```

### Webview contents

- **Form:** Environment dropdown, export type (agents / tools / flows / all), optional filters.
- **Optional:** Multi-select for agents/tools/flows (if fetched from API or parsed from script output).
- **Progress:** Indicator while running.
- **Log:** Streaming lines via `postMessage`.
- **Summary:** Parsed from `export_report.txt` / `import_report.txt` when done.
- **Link:** Open report file in editor.

### Implementation approaches

**Option A — Extend SyncPanel**

Add a tab or section "Bulk Export (CLI scripts)" in the existing SyncPanel. Reuse the same message pattern; handlers spawn scripts instead of calling REST.

**Option B — New panel**

Create a dedicated "WxO Scripts" webview panel (similar to SyncPanel) with:

- Export form
- Import form (folder picker)
- Compare form
- Replicate form
- Log/progress area
- Link to open report when done

---

## Practical considerations

| Topic | Notes |
|-------|-------|
| **Credentials** | Scripts use `.env` and `orchestrate env activate`. Spawn inherits env; ensure `.env` is loaded and orchestrate env is activated before running (or have the script handle it). |
| **Paths** | Scripts expect `WXO_ROOT` or `--output-dir`. Align with extension `wxoPaths.ts` (getWxORoot, getExportPath) or configure `wxo-builder.exportRoot`. Script dir: `internal/WxO ImporterAndExport/` relative to workspace. |
| **Report parsing** | Scripts write `Report/export_report.txt`, `Report/import_report.txt`. Extension can read and parse to show a structured summary in the webview. |
| **Non-interactive** | Scripts accept full CLI args — no `read -p` when `--env`, `--no-credential-prompt`, filters, etc. are passed. |
| **orchestrate CLI** | Must be on PATH. Extension can check `command -v orchestrate` and show install link if missing. |

---

## Path alignment

The extension's `wxoPaths.ts` defines:

- `getWxORoot()` — default: `{workspaceRoot}/WxO`
- `getExportPath(instanceId)` — `WxO/Exports/{instanceId}/{timestamp}/`
- `getImportPath(instanceId)` — `WxO/Imports/{instanceId}/{timestamp}/`

The scripts use:

- `WxO/Exports/<System>/<DateTime>/` 
- `WxO/Replicate/<Source>_to_<Target>/<DateTime>/`
- `WxO/Compare/<Env1>-><Env2>/<DateTime>/`

Ensure both use the same WxO root (via `WXO_ROOT` env var or `wxo-builder.exportRoot` setting).

---

## Making dependency setup easier

Users must install the **orchestrate CLI**, **jq**, and **unzip** before running the scripts. Below are ideas to streamline this.

### Dependencies overview

| Dependency | Purpose | Scripts |
|------------|---------|---------|
| **orchestrate CLI** | IBM watsonx Orchestrate Agent Development Kit (ADK) — agents, tools, flows, connections. **ADK 2.5.0+** recommended | All |
| **jq** | JSON parsing for `orchestrate` output | Main, export, compare |
| **unzip** | Extracting agent/tool bundles | Export |
| **Python 3.11+** | Required for orchestrate CLI (`pip install ibm-watsonx-orchestrate`) | — |

### Installation commands by platform

**orchestrate CLI** (ADK 2.5.0+ recommended):

```bash
# pip (system or venv)
pip install --upgrade ibm-watsonx-orchestrate

# pin to 2.5.0+
pip install 'ibm-watsonx-orchestrate>=2.5.0'

# with uv
uv add ibm-watsonx-orchestrate
```

**jq** — macOS: `brew install jq` · Linux: `apt-get install jq` or `dnf install jq`  
**unzip** — macOS: usually preinstalled · Linux: `apt-get install unzip` or `dnf install unzip`

Official docs: https://developer.watson-orchestrate.ibm.com/getting_started/installing

### Ways to make setup easier

#### 1. Setup script (CLI) ✓

`setup_dependencies.sh` (in this folder):

- Detects platform (macOS vs Linux)
- Checks for Python 3.11+, pip
- Prompts to install orchestrate: `pip install --upgrade ibm-watsonx-orchestrate`
- Installs jq/unzip via brew or apt/dnf (with `sudo` prompt)
- Verifies: `orchestrate --version`, `jq --version`
- Prints next steps (e.g. configure `.env`)

```bash
./setup_dependencies.sh              # check only
./setup_dependencies.sh --install    # prompt to install missing
```

#### 2. VS Code extension: pre-flight check

Before running scripts from the extension:

- Check `command -v orchestrate`, `command -v jq`
- If missing, show a webview or Quick Pick:
  - "orchestrate CLI not found. [Install via pip] [Open install docs] [Run in terminal]"
- "Run in terminal" → open terminal and paste:
  ```bash
  pip install --upgrade ibm-watsonx-orchestrate && brew install jq  # or apt-get
  ```

#### 3. Webview "Setup" tab

Add a **Setup** tab to the WxO Scripts webview:

- Checklist: ☐ orchestrate CLI · ☐ jq · ☐ unzip · ☐ Python 3.11+
- "Check" button → extension runs checks, updates checklist
- Missing items show platform-specific install commands (copy button)
- "Run install commands" → opens terminal with commands (user confirms)

#### 4. One-click terminal install

Extension command: **"WxO: Install dependencies"**

1. Detects OS (Darwin vs Linux)
2. Creates terminal with pre-filled commands:
   - `pip install --upgrade ibm-watsonx-orchestrate`
   - `brew install jq` (macOS) or `sudo apt-get install -y jq unzip` (Linux)
3. User runs them; extension can re-check after.

#### 5. Dev Container / devcontainer.json

For repo contributors, add `.devcontainer/devcontainer.json` that installs orchestrate, jq, unzip in the container. One-time setup for anyone using Dev Containers.

### Recommended combination

1. **Add `setup_dependencies.sh`** — single script users run for CLI setup.
2. **Extension pre-flight** — before first use of WxO Scripts panel, check deps and show install link / terminal commands if missing.
3. **Optional Setup tab** — in webview, show status and copy-paste commands; "Run in terminal" for convenience.

---

## Recommended approach

1. **Add a "WxO Scripts" or "Bulk CLI" section** to SyncPanel or create a new panel.
2. **Webview form** — environment, action (Export/Import/Compare/Replicate), options (agents/tools/flows), filters.
3. **Extension handlers** — map form payload to script CLI args, spawn script, stream output to webview.
4. **On completion** — read report file, parse summary, post to webview; provide link to open report.
5. **Path config** — use `wxo-builder.exportRoot` or `WXO_ROOT` so extension and scripts share the same WxO tree.

---

## Summary

| Question | Answer |
|----------|--------|
| Can the VS Code extension interact with the scripts? | **Yes** — via Terminal API or `child_process.spawn`. |
| Can interaction move to webviews? | **Yes** — same pattern as SyncPanel; handlers spawn scripts instead of calling REST. |
| Best option? | **Webview-driven UI** — consistent UX, live log, parsed reports, single place for all WxO operations. |

---

**Related files**

- `internal/WxOImporterAndExporter/` — scripts (root)
- `internal/WxOImporterAndExporter/vscode-extension/` — standalone extension (independent of wxo-builder)
- `internal/WxOImporterAndExporter/vscode-extension/src/panels/WxOScriptsPanel.ts` — webview (Export/Import/Compare/Replicate)
