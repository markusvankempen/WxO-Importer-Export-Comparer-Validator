# Changelog

All notable changes to the **WxO Importer/Export/Comparer/Validator** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.8] - 2026-03-01

### Added
- **Plugin export/import**: Tools with `binding.python.type` = `agent_pre_invoke` or `agent_post_invoke` are exported to `plugins/<name>/` and imported from `plugins/`. New options: `--plugins-only` (export/import), Export menu [4] Plugins, Import menu [4] Plugins, Folder (all) includes plugins.
- **run_wxo_tests.sh**: Added `export_plugins_only` and `import_plugins_only` test cases
- **VALIDATION_GUIDE.md**: New guide for testing TZ1 ↔ TZ2 validation

### Changed
- **.env lookup**: Scripts now look for `.env` at (in order): `watson-orchestrate-builder/.env`, `watsonx-orchestrate-devkit/.env`, `wxo-toolkit/.env`

### Fixed
- **import_to_wxo.sh**: Fixed missing `fi` for outer tools/plugins import block (syntax error)

---

## [1.0.7] - 2026-02-26

### Changed
- **Export/Replicate menus**: Flows options now clarify that flows can include tools, agents, and connections (e.g. `[3] Flows only (can include tools, agents, connections)`)

---

## [1.0.6] - 2026-02-26

### Added
- **DEFAULT_LLM**: In `.env_connection_<System>`, add `DEFAULT_LLM=groq/openai/gpt-oss-120b`; agents with no `llm` field get this model on import. Fallback: `WXO_LLM` in `.env`.

### Changed
- **Replicate credentials**: Replicate import now uses source env's `.env_connection_<Source>` (e.g. TZ1) instead of target — same API keys apply when copying to TZ2
- **Replicate**: Export no longer creates `WxO/Systems/<Source>_to_<Target>/Connections/`; use source's connection file

---

## [1.0.5] - 2026-02-26

### Added
- **Delete report**: Danger Zone saves a delete report to `WxO/Delete/<System>/<DateTime>/Report/delete_report.txt` with a table of deleted resources (type, name, status, notes) and summary counts

### Fixed
- **Connection credentials on macOS**: `import_tool_with_connection.sh` used `\s` in grep (GNU extension); BSD grep on macOS does not support it, so `kind: basic` was never matched and basic auth credentials were ignored. Replaced with POSIX `[[:space:]]` for macOS/Linux compatibility.

### Removed
- **Copy (Option 5)**: Removed duplicate Copy action; consolidated into Replicate

### Changed
- **Replicate (Option 5)**: Now the single source→target copy flow; uses `WxO/Replicate/<Source>_to_<Target>/<DateTime>/` (separate from Exports)
- **Danger Zone** renumbered to [6] (was [7])
- **Import source**: Can now choose "From Exports" or "From Replicate" when selecting import directory
- Replicate offers finer-grained choices: agents (with/without deps), tools (with/without connections), flows, all, connections

---

## [1.0.4] - 2026-02-25

### Added
- **Version and author in menu**: Main menu header shows version and author (Markus van Kempen); `--version` / `-v` also displays author

### Changed
- Bumped version to 1.0.4 across all scripts

---

## [1.0.3] - 2026-02-25

### Added
- **Back option [0]**: Return to previous menu at each step — environment selection has [0] Exit; action menu and sub-menus (directory, export/import/copy options, validate) have [0] Back
- **Path breadcrumb**: Shows current navigation path (e.g. `Home > TZ1 > Export > Directory`) above each menu
- **Breadcrumb selections**: Each breadcrumb step displays the user's choice (e.g. `Directory: TZ1 — 20260225_125820`, `What to export: Agents (2)`, `Source & Target: TZ1 → TZ2`)
- **Copy report** (`copy_report.txt`): Combined report for Copy action — Copy metadata (source, target, if-exists), full export report, full import report; saved to `WxO/Copy/<Source>_to_<Target>/<DateTime>/Report/copy_report.txt`

### Fixed
- **Import report — skipped visibility**: When `--if-exists skip` is used, the report now clearly shows SKIPPED status for resources that already exist
  - Strip leading non-JSON lines (e.g. `[INFO]`) from `orchestrate tools/agents/connections list` output so existing-resource detection works correctly
  - Cache existing resources list once per import run instead of refetching for each check
  - Summary shows per-type skipped counts: `agents: ✓ N OK, ⏭ M skipped, ✗ P failed | tools: ... | connections: ...`

### Changed
- **Navigation loop**: Main script uses nested loops so Back from sub-menus returns to the action menu (not full restart)

---

## [1.0.2] - 2026-02-25

### Fixed
- **Connections export parsing**: Portable first-line strip (macOS BSD sed compatible); filter only `environment == "live"` (exclude draft/unspecified)
- **Intrinsic tools**: Skip tools with `intrinsic` in name (platform-built, not exportable); report as SKIPPED
- **Catalog skills**: Skip tools with `binding.skill` (IBM prebuilt); report as SKIPPED; detect catalog skills from export failure ("could not find uploaded OpenAPI specification") and record as SKIPPED

### Added
- **Copy (Option 5)**: Copy agent/flow/tool (and dependencies) from source to target environment — select source env, target env, what to copy (agents/tools/flows/connections/all); export from source, import to target; report in `WxO/Copy/<Source>_to_<Target>/<DateTime>/Report/`
- **ORCHESTRATE_COMMANDS.md**: Internal reference for orchestrate CLI commands, use cases, output paths, JSON structures
- **tools/Dad_Jokes_Skill/**: Exportable `skill_v2.json` for re-import via CLI (fix for tools created without uploaded spec)

---

## [1.0.1] - 2026-02-25

### Added
- **Connections (live) export/import**: `--connections-only` to export live connections to `connections/<app_id>.yml` and import from `connections/`

---

## [1.0.0] - 2026-02-25

### Added
- **Main interactive script** (`wxo_exporter_importer.sh`): Environment selection, Export/Import/Compare/Validate workflows
- **Export** (`export_from_wxo.sh`): Agents with dependencies, tools (Python/OpenAPI/Flow), flows-only option
- **Import** (`import_to_wxo.sh`): Agents, tools, flows from `agents/`, `tools/`, `flows/` directories; `--if-exists skip|override`; optional validation
- **Compare** (`compare_wxo_systems.sh`): Agents, tools, flows diff between two WXO environments with report table
- **Validate**: Invoke agents with test prompt; optionally compare responses between two systems
- **Flows directory**: Flow tools exported to `flows/` (separate from `tools/`); import from `flows/` supported
- **Export report**: Formatted report in `WxO/Exports/<System>/<DateTime>/Report/export_report.txt`
- **Import report**: `WxO/Imports/<TargetEnv>/<DateTime>/Report/import_report.txt`
- **Validation report**: `WxO/Validate/<Env>/<DateTime>/validation_report.txt` or `WxO/Validate/<Target>-><Source>/<DateTime>/validation_report.txt`
- **User guide** (`USER_GUIDE.md`): Step-by-step instructions, UI walkthrough, options for all four use cases
- **Debug logging**: `WXO_DEBUG=1` or `WXO_LOG=1` for `WxO/logs/wxo_debug_YYYYMMDD.log`
- **.env support**: `WXO_URL_<ENV>`, `WXO_API_KEY_<ENV>` for API keys and instance URLs

### Fixed
- **Flows-only export**: Menu option [3] now correctly passes `--flows-only` (previously exported everything)
- **Flows directory**: Flow tools written to `flows/<name>/` instead of `tools/<name>/`; import accepts `flows/` source

### Changed
- Export structure: `agents/`, `tools/`, `flows/`, `connections/`, `Report/`
- Import validation: accepts `agents/`, `tools/`, `flows/`, or `connections/` directory
- Compare report: aligned format with console output

---

## Original

Inspired by **Ajit Kulkarni** <ajit.kulkarni2@ibm.com>.  
Source: [github.ibm.com/ICA/watsonXOrchetrate_auto_deploy](https://github.ibm.com/ICA/watsonXOrchetrate_auto_deploy)
