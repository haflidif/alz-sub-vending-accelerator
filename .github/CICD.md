# `.github/` — CI/CD machinery

The skeleton ships everything CI needs to validate PRs and apply
subscriptions on merge. GitHub Actions only — **no external runners, no
shared service-principal secrets**. Auth is OIDC →
UAMI federation; every workflow runs inside the operator's tenant.

## Files

| Path | Purpose |
|---|---|
| [`workflows/pr-validate.yml`](workflows/pr-validate.yml) | Runs on every PR. Validates YAML and accelerator contracts, discovers affected subscriptions, then runs Terraform plan or Bicep validate/what-if and posts the preview as a PR comment. |
| [`workflows/apply.yml`](workflows/apply.yml) | Runs on `push` to `main` and `workflow_dispatch`. Discovers affected subscriptions and deploys them with the selected engine behind the `production` GitHub Environment gate. |
| [`scripts/discover-subs.sh`](scripts/discover-subs.sh) | Single bash script consumed by **both** workflows. Emits a `matrix` JSON listing every `(sub_path, archetype, name, state_key)` to operate on. |
| [`dependabot.yml`](dependabot.yml) | Weekly updates for GitHub Actions pins, monthly updates for the `terraform/` and `bootstrap/` providers. |
| [`PULL_REQUEST_TEMPLATE.md`](PULL_REQUEST_TEMPLATE.md) | PR description scaffold — change type + per-track checklists. |
| `CODEOWNERS` | **Rendered by `bootstrap/` from `bootstrap/templates/CODEOWNERS.tftpl`** — not in this skeleton checkout. Auto-requests reviews from the operator-chosen team(s) for each path. |

## Trigger matrix

| Event | Workflow | Mode | Selection |
|---|---|---|---|
| `pull_request` to `main` | `pr-validate.yml` | always `changed` | Subs whose YAML added/modified vs `origin/<base_ref>` |
| `push` to `main` | `apply.yml` | `changed` | Subs whose YAML changed between `before` and `sha` |
| `workflow_dispatch` (apply) | `apply.yml` | `changed` / `single` / `all` | Operator-selected. `single` needs `sub_path`; `all` re-applies every `landingzones/*/*.yaml`. |

## `discover-subs.sh` — modes

Single source of truth for "which subscriptions does this run touch?"

| Mode | Inputs | Behaviour |
|---|---|---|
| `changed` | `BASE`, `HEAD` env vars | `git diff --name-only --diff-filter=AM "$BASE...$HEAD" -- 'landingzones/*/*.yaml'` |
| `single` | `SUB_PATH` env var | Exactly one sub. Accepts either `landingzones/corp/prod-corp-erp-001.yaml` OR the `.yaml`-less stem (`landingzones/corp/prod-corp-erp-001`). |
| `all` | (none) | `find landingzones -mindepth 2 -maxdepth 2 -type f -name '*.yaml'` |

Output written to `$GITHUB_OUTPUT`:
- `matrix=<json>` — `{"include":[{"sub_path":"…","archetype":"…","name":"…","state_key":"…/….tfstate"}]}`
- `count=<int>` — used by downstream jobs as `if: needs.discover.outputs.count != '0'`

`state_key` is always `<archetype>/<name>.tfstate` — this is what the
`terraform init -backend-config="key=…"` step in each job uses. Per-sub
state isolation is enforced here. Bicep ignores this compatibility field.

`VENDING_ENGINE` must be `terraform` or `bicep`. A change to Terraform
runtime `.tf` files selects all requests in a Terraform repository. A change
to Bicep templates, the request compiler, `platform.json`, or
`default-resource-providers.json` selects all requests in a Bicep repository.

## How the `apply.yml` matrix runs

1. **`discover` job** — runs `discover-subs.sh`, emits the matrix.
2. The matching engine job fans out over the matrix, with at most five
   subscriptions in parallel:
   - Logs into Azure via `azure/login@v3` using OIDC against the operator's UAMI (FIC matches the trigger — branch / PR / environment).
   - Terraform initializes the per-sub backend, creates a saved plan, applies
     it, captures structured Terraform outputs, and uploads the plan and
     output artifacts.
   - Bicep compiles the YAML request, starts `az deployment mg create`
     asynchronously, and reports the Azure provisioning state every 30
     seconds.

Both engines publish a GitHub job summary containing the request path,
deployment status, subscription ID, and engine-specific operational details.
The Bicep summary also reports the stable deployment name, budget resource ID,
and any resource-provider registration failures. Failed Bicep deployments add
the Azure error object to the summary and retain the deployment response as an
artifact.

The `production` GitHub Environment gates every job in this matrix —
required reviewers are configured by `bootstrap/` from
`production_reviewer_user_ids` / `production_reviewer_team_ids`.

## OIDC subject claims (federated credentials)

`bootstrap/` creates **three** federated identity credentials on the
pipeline UAMI, matching the workflows' trigger contexts:

| Display name | Subject | Used by |
|---|---|---|
| `github-branch-main` | `repo:<owner>/<repo>:ref:refs/heads/main` | `push` to `main` |
| `github-pull-request` | `repo:<owner>/<repo>:pull_request` | `pull_request` (any branch) |
| `github-env-production` | `repo:<owner>/<repo>:environment:production` | jobs that declare `environment: production` (i.e. `apply.yml`) |

If you rename `main` or the production environment, both the FIC subject
and the workflow YAML must change in lock-step.

## Required repo variables

`bootstrap/` writes these as Actions repository variables on the seeded
repo:

| Variable | Source | Used by |
|---|---|---|
| `AZURE_CLIENT_ID` | `azurerm_user_assigned_identity.pipeline.client_id` | `azure/login@v3` |
| `AZURE_TENANT_ID` | Platform sub's tenant ID | `azure/login@v3` + `terraform init -backend-config=tenant_id=` |
| `AZURE_SUBSCRIPTION_ID` | `platform_subscription_id` | `azure/login@v3` + `terraform init -backend-config=subscription_id=` |
| `VENDING_ENGINE` | Selected starter | Workflow routing and discovery validation |
| `ALZ_ROOT_MANAGEMENT_GROUP_ID` | ALZ root management group | Bicep validation, what-if, and deployment scope |
| `AZURE_DEPLOYMENT_LOCATION` | Bootstrap deployment location | Bicep management-group deployment location |
| `BACKEND_RESOURCE_GROUP_NAME` | Terraform only: platform state SA's RG | `terraform init` |
| `BACKEND_STORAGE_ACCOUNT_NAME` | Terraform only: platform state SA name | `terraform init` |
| `BACKEND_CONTAINER_NAME` | Terraform only: runtime state container | `terraform init` |

Plus `AZAPI_RETRY_GET_AFTER_PUT_MAX_TIME=60m` (env-level only, not a
repo variable) — covers slow subscription-alias propagation.

## Required status checks

`bootstrap/` configures branch protection on the default branch with
two required check contexts (matches `pr-validate.yml` job names exactly):

```
PR Validate / YAML schema validation
PR Validate / PR Validate Result
```

Renaming either job in `pr-validate.yml` requires updating
`branch_protection_required_status_checks` in `bootstrap/terraform.tfvars`
(or directly in the seeded repo's branch protection settings if you don't
re-run `bootstrap/`).

## Dependabot cadence

| Ecosystem | Directory | Schedule |
|---|---|---|
| `github-actions` | `/` | weekly |
| `terraform` | `/terraform` | weekly |
| `terraform` | `/bootstrap` | monthly |

Teams with stricter change-management windows usually slow these
down — see
[`docs/onboarding.md → "Tuning Dependabot cadence"`](../docs/onboarding.md#tuning-dependabot-cadence).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Expected — Waiting for status to be reported` on a PR that doesn't touch `landingzones/` | The `plan` matrix has `count=0` so the job didn't run. The required check `PR Validate Result` should still report. | Confirm the `PR Validate / PR Validate Result` check appears; if not, branch protection is referencing a job name that doesn't exist (rename mismatch). |
| `AADSTS70021: No matching federated identity record found` | The workflow's subject claim doesn't match any FIC on the UAMI. | Re-check `repo:<owner>/<repo>:…` in the FIC vs the workflow's trigger context. If you renamed `main` or the `production` environment, update the FIC. |
| Preview succeeds in PR but `apply` blocks forever | No reviewer has approved the `production` environment. | Settings → Environments → `production` → review the run, or update the environment reviewers in GitHub Settings. |
| `Error: state blob is already locked` | A previous `apply` job died without releasing the lease. | Azure portal → state SA → container → blob → break lease. Or `terraform force-unlock <lock-id>` from a workstation that has access. |
| `mode=single` workflow_dispatch fails with `not found: …` | `SUB_PATH` doesn't resolve to a real file. | `discover-subs.sh` will append `.yaml` if missing — check the typed path and the actual filename. |

## See also

- [`docs/onboarding.md`](../docs/onboarding.md) — one-time operator setup
- [`docs/first-vend.md`](../docs/first-vend.md) — vend your first sub
- [Bootstrap reference](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md)
- [`docs/state-storage.md`](../docs/state-storage.md) — backend container + per-sub key
- [GitHub OIDC with Azure](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
