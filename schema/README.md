# Iron Dome — JSON Schemas

Machine-readable [JSON Schema](https://json-schema.org/) (Draft-07) for Iron Dome
configuration files. Enables editor autocomplete + inline validation, and a CI gate.

| File | Validates |
|------|-----------|
| `iron-dome.schema.json` | `iron-dome.yml` and `examples/*.yml` (full guard config) |
| `iron-dome.override.schema.json` | `.iron-dome.yml` (per-repo overrides: `disabled_patterns`, `additional_patterns`) |

## Editor (VS Code + YAML extension)

Two mechanisms, both committed:

1. **Workspace mapping** — `.vscode/settings.json` maps the config files to these
   schemas via `yaml.schemas`. Works as soon as the repo is opened.
2. **Modeline** — `iron-dome.yml` carries a `# yaml-language-server: $schema=...`
   comment so the schema is picked up even outside this workspace.

## CI

`src/ci/schema-validate.sh` validates `iron-dome.yml` + `examples/*.yml` against the
schema. It is also exercised by the test suite (`tests/test_schema.sh`), so it runs
wherever `tests/run-tests.sh` runs. Zero hard dependency: it auto-selects
`check-jsonschema`, then `python3 + jsonschema + PyYAML`, and degrades to a clear
skip if neither is available (never a false failure).

## Publishing to SchemaStore (optional)

To make the schema available to any editor without local config, submit it to
[SchemaStore](https://www.schemastore.org/):

1. Fork `SchemaStore/schemastore`.
2. Add the raw URL of `iron-dome.schema.json` to `src/api/json/catalog.json`
   with `fileMatch: ["iron-dome.yml", ".iron-dome.yml"]`.
3. Open a PR. Once merged, editors resolve the schema automatically.

The `$id` in each schema already points at the canonical raw GitHub URL.
