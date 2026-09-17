# Vending your first subscription

Once `bootstrap/` has been applied and the GitHub repo is seeded, day-to-day
sub-vending is a YAML-and-PR loop. This page walks you through it once.

> Prereqs: you completed [`onboarding.md`](onboarding.md) — repo exists,
> pipeline UAMI has roles, `production` environment has reviewers, and
> the selected engine configuration (`terraform/terraform.auto.tfvars` or
> `bicep/platform.json`) is present in the repo.

## 1. Pick an archetype

| Archetype | Lands under | Workload default | Typical use |
|-----------|-------------|------------------|-------------|
| `corp`    | `mg-corp`   | `Production`     | Internal apps, peered to hub |
| `online`  | `mg-online` | `Production`     | Internet-facing apps, peered to hub |
| `sandbox` | `mg-sandbox`| `Production` (override to `DevTest` if entitled) | Disposable experiments, **budget required** |

See [`archetypes.md`](archetypes.md) for the full rules.

## 2. Create the YAML

Naming convention is `<env>-<archetype>-<workload>-<###>.yaml`. Pick the
next free `###`.

```bash
# from a fresh feature branch
git switch -c feat/vend-prod-corp-erp-001

# Copy the example for your archetype as a starting point
cp landingzones/corp/prod-corp-erp-001.yaml landingzones/corp/<your-sub-name>.yaml
$EDITOR landingzones/corp/<your-sub-name>.yaml
```

Minimum fields (everything else inherits from the archetype):

```yaml
archetype:   corp                   # REQUIRED — corp | online | sandbox
location:    westeurope             # REQUIRED — no default
owner:       team@example.com       # REQUIRED — business owner email

displayName: "ERP — Production"
aliasName:   prod-corp-erp-001
workload:    Production             # Production | DevTest
tags:
  costCenter: "12345"
  dataClass:  internal
```

Sandbox additionally **requires** a `budget:` block with an `amount` — the
schema validator will fail the PR if it is missing.

## 3. Open a PR

```bash
git add landingzones/corp/prod-corp-erp-001.yaml
git commit -m "feat(corp): vend prod-corp-erp-001"
git push -u origin HEAD
gh pr create --fill
```

Two checks run automatically:

1. **Validate sub YAML schema** — fast, fails on missing/bad fields.
2. **Preview changed subscriptions**. Runs Terraform plan or Bicep what-if
   with OIDC, then posts the output as an artifact and PR comment. Read this
   before approving.

## 4. Merge → apply

When the PR is merged to `main`:

- The push to `main` triggers `apply.yml`.
- Discovery diffs the merge against the previous commit and produces a matrix
  of changed YAMLs.
- The job pauses on the `production` environment gate. The reviewers
  configured during bootstrap get a notification.
- After approval, the selected engine deploys **per subscription, in
  parallel**. Terraform uses isolated state
  (`<arch>/<name>.tfstate` in `subvending-tfstate`); Bicep uses
  management-group deployments.

Each apply takes ~3–8 minutes for a fresh subscription (creating the alias,
moving it under the MG, registering providers, optional VNet + peering, role
assignments, UAMI + federated credentials).

## 5. Re-run a single sub

If one matrix item failed but the rest succeeded, you don't need a new PR:

1. Actions → **Apply** → **Run workflow**
2. `mode = single`, `sub_path = landingzones/corp/prod-corp-erp-001`
3. Wait for the production gate, approve, watch logs.

## 6. Modifying an existing sub

Edit the YAML and open a PR. Terraform plan or Bicep what-if shows what will
change in Azure, such as a new role assignment, VNet, or tag. Deployment
follows the same merge and environment-gate path.

> Note: deleting a YAML does **not** delete the Azure subscription. To
> retire a sub, see [`teardown.md`](teardown.md).

## Troubleshooting

| Symptom | Most likely cause |
|---------|-------------------|
| `EntitlementNotFound: MS-AZR-0148P` on sandbox | EA admin hasn't enabled Dev/Test pricing on the enrollment. Use `Production` (default) or have them enable it. |
| `BillingAccountIdMissing` / `403` on alias creation | Pipeline UAMI is missing `SubscriptionCreator` on the billing scope. Re-run `Grant-SubscriptionCreatorRole` (see onboarding doc). |
| `Subscription_NotFound` mid-apply | Azure Resource Manager hasn't fully propagated the new sub yet. The AzAPI provider retries automatically; if it still fails after 60m, re-run the matrix item. |
| Apply hangs at "Waiting for review" | Check Settings → Environments → `production`; required reviewers must explicitly approve. |
| The preview matrix is empty on a PR | `discover-subs.sh` could not see the YAML or selected-engine change. Confirm the request is at `landingzones/<archetype>/<name>.yaml` and `VENDING_ENGINE` is `terraform` or `bicep`. |
