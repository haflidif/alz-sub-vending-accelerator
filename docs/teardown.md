# Tearing down a vended subscription

Subscription **cancellation** in Azure is a soft delete — the subscription
enters `Disabled` state for 90 days before being permanently deleted by the
platform. The same applies to its Terraform state: deleting the state alone
will not delete Azure resources, and cancelling the subscription will not
remove the state. Doing both, in the right order, is the operator's job.

This document is the canonical tear-down runbook. Follow it whenever you
need to retire a vended subscription, whether the workload is moving
elsewhere, the business has gone away, or you are cleaning up after a
failed test.

---

## When to use which path

| Situation | Path |
|---|---|
| You vended a sub by mistake (no real workload data yet) and want it gone | **Path A — Destroy** |
| The subscription has real workload data that must be archived first | **Path B — Cancel then archive** |
| You want to keep the subscription but stop the pipeline from managing it | **Path C — Detach** |

All three paths start by removing the sub YAML from the seeded repo. The
difference is what you do about Azure-side state.

---

## Pre-requisites for any tear-down

1. You can authenticate as the pipeline UAMI (or a user with equivalent
   permissions) — same identity that originally vended the subscription.
2. You have access to the state container that the pipeline uses
   (`<state SA>/subvending-tfstate/<archetype>/<name>.tfstate`).
3. The subscription is **not** the connectivity subscription, the
   management subscription, or any other shared platform sub. Those are
   managed by the platform team's own Terraform — not by sub-vending.

---

## Path A — Destroy (workload retired with the subscription)

Use this when the subscription contained nothing worth keeping. Result: the
subscription is cancelled in Azure, every Terraform-managed resource group
is force-deleted, the state blob is removed, and the YAML is gone.

### A.1 — Run `terraform destroy` from your workstation

```powershell
# Clone the seeded repo and authenticate to Azure
gh repo clone <github_owner>/<repo>
cd <repo>/terraform

az login --tenant <tenant-id>
$env:GITHUB_TOKEN = (gh auth token)

# Recreate the same backend init the pipeline uses
$arch = 'corp'
$name = 'prod-corp-erp-001'
terraform init `
  -backend-config="resource_group_name=$env:BACKEND_RESOURCE_GROUP_NAME" `
  -backend-config="storage_account_name=$env:BACKEND_STORAGE_ACCOUNT_NAME" `
  -backend-config="container_name=$env:BACKEND_CONTAINER_NAME" `
  -backend-config="key=$arch/$name.tfstate" `
  -backend-config="tenant_id=$env:AZURE_TENANT_ID" `
  -backend-config="subscription_id=$env:AZURE_SUBSCRIPTION_ID"

$env:TF_VAR_sub_yaml_path = "../landingzones/$arch/$name.yaml"
terraform destroy
```

Confirm the plan removes **only** the resource groups created by the AVM
module (typically the workload RGs and `NetworkWatcherRG`) plus the
subscription alias. Apply.

> The AVM module **does not** cancel the subscription on `terraform
> destroy`; subscription aliases are separate from subscription state. The
> alias is removed (which removes the friendly name) but the subscription
> itself stays alive until you cancel it via `az account subscription
> cancel`.

### A.2 — Cancel the Azure subscription

```bash
SUB_ID=$(az account subscription show --subscription "<sub-name>" --query subscriptionId -o tsv)
az account subscription cancel --subscription-id "$SUB_ID" --yes
```

The subscription enters `Disabled` state. After 90 days it is permanently
deleted by the platform. During those 90 days you can reactivate it via
the Azure portal if needed — useful insurance for the first 30 days.

### A.3 — Remove the YAML and clean the state blob

```powershell
# In the seeded repo
git rm landingzones/$arch/$name.yaml
git commit -m "feat: retire $arch/$name (Azure sub cancelled $(Get-Date -Format yyyy-MM-dd))"
git push

# Delete the state blob (the destroy above already emptied it, but the
# blob itself lingers until you remove it explicitly)
az storage blob delete `
  --account-name $env:BACKEND_STORAGE_ACCOUNT_NAME `
  --container-name $env:BACKEND_CONTAINER_NAME `
  --name "$arch/$name.tfstate" `
  --auth-mode login
```

A `feat: retire …` PR that only deletes a sub YAML is harmless — the
discover script in `pr-validate.yml` reports `count=0` and the plan matrix
skips. The destroy and the YAML removal can happen in either order.

---

## Path B — Cancel then archive (workload data must outlive the sub)

Use this when there is data in storage accounts, key vaults, log workspaces,
etc. that must be retained for compliance or migration.

1. **Move out anything that should survive** — replicate storage accounts,
   export Key Vault secrets, redirect log streams, etc. The platform team
   should agree on the retention model before you start.
2. **Cancel the subscription** (Step A.2). Disabled subs do not let you
   provision new resources but existing data remains accessible for the
   90-day grace window.
3. **Wait for the grace window to expire**, or wait long enough that you
   trust the export.
4. **Remove the YAML** (Step A.3, but skip the `terraform destroy` — the
   subscription cancellation eventually deletes the resources for you).
5. **Delete the state blob** (Step A.3, blob delete only). The state is
   now describing a subscription that no longer exists; keeping it around
   risks confusing future operators.

---

## Path C — Detach (keep the subscription, stop managing it)

Use this when the workload team wants to take over the subscription
themselves (e.g. they prefer Bicep, or they have their own Terraform
estate) but the subscription should keep existing.

1. **Stop pipeline management.** Open a PR that removes the YAML; merge.
2. **Strip the state.** Run `terraform state rm 'module.subscription'`
   followed by `terraform apply` (a no-op apply on empty state) — this
   tells Terraform to forget the resources without destroying them. The
   resources remain in Azure exactly as they are.
3. **Reassign ownership.** Move the subscription to a different MG (or
   not), grant the new owners RBAC at the subscription scope, and
   document the change.
4. **Delete the state blob** (Step A.3, blob delete). Same reasoning as
   Path B.

> Detached subscriptions are no longer governed by the sub-vending
> pipeline's tag policy, role assignments, or peering rules. The new
> owners are responsible for everything from this point forward.

---

## Validation after tear-down

After any path, confirm the cleanup:

```bash
# 1. The sub YAML is gone from main
git -C <repo> ls-files landingzones/$arch/ | grep "$name"

# 2. The state blob is gone
az storage blob exists `
  --account-name $env:BACKEND_STORAGE_ACCOUNT_NAME `
  --container-name $env:BACKEND_CONTAINER_NAME `
  --name "$arch/$name.tfstate" `
  --auth-mode login

# 3. The subscription is Disabled (Path A/B) or its owner has changed
#    (Path C). Disabled subs return state=Disabled.
az account subscription show --subscription "<sub-name>" --query state -o tsv
```

If any of these still show the old state, repeat the relevant step. The
runbook is idempotent — re-running a destroy on already-destroyed state is
a no-op, and `az account subscription cancel` is safe to re-issue.

---

## What about the pipeline UAMI / state container / GitHub repo?

These are **platform-level** resources, created by `bootstrap/`. You only
need to remove them when you are decommissioning the entire platform
(decommissioning the entire tenant). For that, run `terraform destroy` against
`bootstrap/` from the original operator workstation (which still has the
bootstrap's local state). The destroy removes the UAMI, the OIDC
federations, the state container, branch protection, the production
environment, and unlinks the GitHub repo file resources. The repo itself
is left alone unless `create_github_repository = true` was set; in that
case it is removed too.

Do **not** destroy `bootstrap/` while any vended subscription is still
live — its UAMI is the only identity that can apply changes to those
subs.
