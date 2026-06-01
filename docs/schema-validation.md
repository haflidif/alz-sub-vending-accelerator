# YAML schema validation

Every subscription contract under `landingzones/<archetype>/<name>.yaml` is validated
against [`landingzones/sub.schema.json`](../landingzones/sub.schema.json) — a
JSON Schema (Draft 2020-12) that defines required fields, allowed values, regex
patterns and conditional rules.

## Where validation runs

| Stage | How | What happens on failure |
|---|---|---|
| **Editor (live)** | `# yaml-language-server: $schema=../sub.schema.json` directive at top of every YAML file | Red squiggles + hover hints in VS Code (requires the [YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)). |
| **Pre-commit (optional)** | `pipx install check-jsonschema && check-jsonschema --schemafile landingzones/sub.schema.json landingzones/*/*.yaml` | Local error before push. |
| **PR validation (CI)** | `schema-validate` job in `.github/workflows/pr-validate.yml` runs on every PR touching `landingzones/` | PR check fails — `plan` jobs do **not** run on invalid data. |
| **Terraform plan/apply** | Belt-and-suspenders `_assert_*` checks in `terraform/locals.tf` | Plan fails with a clear missing-field message if schema was bypassed. |

## What the schema enforces

| Rule | Why |
|---|---|
| `archetype` ∈ `corp`/`online`/`sandbox` | Must match a folder + a key in `terraform/archetypes.tf`. |
| `location`, `owner` are required | No silent defaults — every sub must declare these. |
| `owner` / `technicalResponsible` / `budget.contacts[*]` are emails | Catches typos like `me@example.con`. |
| `aliasName` matches `^[a-z0-9][a-z0-9-]*[a-z0-9]$` | Azure subscription alias rules. |
| `costAllocationCode` is optional in the schema | Operator decides if it's required and which regex applies — see [docs/tagging.md](tagging.md). |
| `costCenter` is a string of digits/letters/`-` | Preserves leading zeros (`"0042"` ≠ `42`). |
| `billingScopeKey` (optional) selects the billing scope | Defaults to `default` — see [docs/billing-scopes.md](billing-scopes.md). |
| `network.addressSpace[*]` is CIDR `a.b.c.d/x` | Catches malformed prefixes. |
| `network.enabled: true` ⇒ `addressSpace` required | Conditional `if/then`. |
| `archetype: sandbox` ⇒ `budget` required | Sandbox guardrail. |
| `additionalProperties: false` at root | Catches typos like `costCentre` instead of `costCenter`. |

## Adding a new optional field

1. Add the field + description/regex to `landingzones/sub.schema.json`.
2. Read it in `terraform/locals.tf` via `lookup(local.sub, "<field>", <default>)`.
3. Update `docs/architecture.md` schema table.
4. (Optional) add an `_assert_*` local if it should be required.

## Adding a new archetype

1. Add the new value to `properties.archetype.enum` in the schema.
2. Add a folder `landingzones/<new-archetype>/`.
3. Add a key under `archetype_config` in `terraform/archetypes.tf`.
4. Add an MG ID for it directly in the seeded repo's
   `terraform/terraform.auto.tfvars` (`management_group_ids` map). The
   bootstrap is one-shot and is **not** re-run for this — see
   [`docs/archetypes.md`](archetypes.md) for the full walkthrough.
