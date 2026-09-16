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
| **Engine validation/deployment** | Terraform `_assert_*` checks or Bicep compiler validation | The selected engine fails with a clear message if schema validation was bypassed. |

## What the schema enforces

| Rule | Why |
|---|---|
| `archetype` ∈ `corp`/`online`/`sandbox` | Must match a folder and the selected engine's archetype configuration. |
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
2. Map and validate it in both engine adapters, or document why it is
   intentionally engine-specific.
3. Update `docs/architecture.md` and engine-specific references.
4. Add regression tests for both engines.

## Adding a new archetype

1. Add the new value to `properties.archetype.enum` in the schema.
2. Add a folder `landingzones/<new-archetype>/`.
3. Add the archetype rules to `terraform/archetypes.tf` and
   `bicep/SubscriptionVending.Bicep.psm1`.
4. Add its management-group ID to the selected engine configuration:
   `terraform/terraform.auto.tfvars` or `bicep/platform.json`.
5. See [`docs/archetypes.md`](archetypes.md) for the full walkthrough.
