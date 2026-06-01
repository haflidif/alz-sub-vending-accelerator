# Tagging strategy

This skeleton's tag model is grounded in the [Cloud Adoption Framework — resource
tagging decision guide](https://learn.microsoft.com/azure/cloud-adoption-framework/decision-guides/resource-tagging/)
and the [Well-Architected Framework — Cost
Optimization](https://learn.microsoft.com/azure/well-architected/cost-optimization/)
pillar. It is intentionally **opinionated but customizable** so the same
skeleton works for every organization regardless of agreement type or chargeback
convention.

> **Tag inheritance is NOT automatic.** Tags applied at subscription level do
> not flow down to resource groups or resources. The platform team must enable
> the relevant Azure Policy aliases (`Inherit a tag from the subscription if
> missing` / `... resource group ...`) at the management-group scope. Cost
> Management has its own separate "tag inheritance" toggle.

---

## Tag layers (lowest → highest priority)

When the same key appears in more than one layer, the **higher-priority layer
wins** (governed tags always win):

| Order | Layer                | Source                                              | Notes                                                 |
| ----: | -------------------- | --------------------------------------------------- | ----------------------------------------------------- |
|     1 | **caller-supplied**  | `tags:` map in `landingzones/<arch>/<sub>.yaml`     | Free-form; reserved keys rejected at plan time        |
|     2 | **mandatory**        | `var.mandatory_tags` (terraform/variables.tf)       | Platform-wide defaults; CAF-aligned                   |
|     3 | **archetype extras** | `local.archetype_config[<arch>].extra_tags`         | E.g. `archetype = "corp"`                             |
|     4 | **identity**         | derived from sub.yaml fields + cost-allocation tag  | Always wins                                           |

### Caller-tag collision check

If a sub.yaml's `tags:` map contains a key that also appears in any governed
layer (identity, mandatory, archetype, or `cost_allocation_tag_key`), Terraform
fails at plan time with the offending keys listed. Add only **net-new**
free-form tags in the `tags:` map.

---

## Tag baseline (CAF-aligned)

All tag **names** use lowercase, no separators (`businessowner`, not
`business-owner`), matching the convention used by the ALZ Accelerator and the
broader CAF guidance.

| Tag key            | Source                        | Required | Purpose                                                                     |
| ------------------ | ----------------------------- | -------- | --------------------------------------------------------------------------- |
| `businessowner`    | `owner`                       | yes      | Business owner email / DL — also used for budget alerts                    |
| `technicalcontact` | `technicalResponsible`        | no       | Defaults to `owner` when omitted                                            |
| `costcenter`       | `costCenter`                  | no       | Finance cost-center code; emits `unassigned` when omitted                   |
| `workloadname`    | `workloadName`                | no       | Human-friendly workload name; defaults to alias                             |
| `environment`      | `workload` (Production/DevTest) | yes    | Lifecycle classifier for FinOps + Cost Management                           |
| `archetype`        | `local.archetype_config`      | yes      | Custom but consistent — identifies the landing-zone archetype               |
| **mandatory_tags** | bootstrap-set defaults        | yes      | Platform-wide constants — `managedby` / `source` / `deployedby`             |
| `<cost-alloc>`    | `costAllocationCode`          | configurable | Operator-configurable; key set via `cost_allocation_tag_key`             |

### Mandatory tag defaults

Set in `bootstrap/variables.tf`, written into the seeded
`terraform/terraform.auto.tfvars`:

```hcl
mandatory_tags = {
  managedby  = "terraform"
  source     = "avm-ptn-alz-sub-vending"
  deployedby = "subscription-vending-pipeline"
}
```

Set the platform-wide default at bootstrap time by adding
`mandatory_tags = { ... }` to your `bootstrap/terraform.tfvars`. After
the initial bootstrap, change them by editing `mandatory_tags` directly in
the seeded repo's `terraform/terraform.auto.tfvars` via a PR — the bootstrap
is one-shot and is **not** re-run for this.

---

## Cost-allocation tag (configurable)

Organizations track cost differently:

* Some use a **finance cost-center only** — the always-on `costcenter` tag is
  enough.
* Some have **project / activity codes** layered on top — e.g.
  `activitycode` with values like `PC016083` (a project-coded
  alphanumeric).
* Some use **WBS elements** from SAP — `wbselement`.
* Some align to **CAF "program" or "appid"**.

The skeleton supports all of these via three operator inputs. At
**initial bootstrap** they live in `bootstrap/terraform.tfvars` and flow into
`terraform.auto.tfvars` in the seeded repo. Post-bootstrap, change them by
editing the seeded repo's `terraform/terraform.auto.tfvars` directly via a
PR — the bootstrap is one-shot and is **not** re-run for value rotations.

```hcl
cost_allocation_tag = {
  name     = "activitycode"             # Tag KEY (lowercase, no separators)
  required = true                       # Fail-fast if a sub.yaml omits costAllocationCode
  pattern  = "^[A-Z]{1,4}[0-9]{4,8}$"   # Optional Terraform regex (anchors recommended)
}
```

| Field      | Default       | Effect                                                                                    |
| ---------- | ------------- | ----------------------------------------------------------------------------------------- |
| `name`     | `projectcode` | Azure tag key for the cost-allocation tag                                                 |
| `required` | `false`       | When `true`, every `sub.yaml` must include `costAllocationCode`                           |
| `pattern`  | `null`        | Optional regex applied at plan time; `null` accepts any non-empty string                 |

### In sub.yaml

```yaml
costAllocationCode: PC016083   # → emitted as <name>=PC016083
```

### Migration note

When a sub already exists in Azure and you change `cost_allocation_tag.name`,
the **old** tag key persists on the Azure side until removed. The next
`terraform apply` writes the **new** key but does not delete the old one.
Run a one-off cleanup with the Azure CLI:

```bash
az tag delete --resource-id <subscriptionId> --name <old-key> --yes
```

---

## Azure Policy tag inheritance (recommended)

After bootstrap, enable these built-in policy assignments at the appropriate
management group so resources inherit subscription tags automatically:

| Policy display name                                                  | Effect    |
| -------------------------------------------------------------------- | --------- |
| Inherit a tag from the subscription if missing                       | `modify`  |
| Inherit a tag from the resource group if missing                     | `modify`  |
| Require a tag on resources                                           | `deny`    |

> **Cost Management tag inheritance** is a separate, billing-side toggle in
> the Azure portal under *Cost Management → Manage → Cost allocation*. It
> backfills tags for **billing**, not for resources. Enable it once per
> billing scope.

---

## See also

* [docs/billing-scopes.md](billing-scopes.md) — billing scope formats and `billing_scopes` map
* [docs/schema-validation.md](schema-validation.md) — sub.yaml schema reference
* [CAF — naming and tagging conventions](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
* [WAF — Cost optimization](https://learn.microsoft.com/azure/well-architected/cost-optimization/)
