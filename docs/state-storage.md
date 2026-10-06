# Terraform state storage

This page applies to the Terraform runtime and to the shared Terraform-based
bootstrap. The Bicep runtime uses Azure management-group deployment history
and has no per-subscription Terraform state.

## Recommendation

Use the **same storage account as the platform** Terraform state, with a
**dedicated container** for vending state.

| Setting | Value |
|---|---|
| Subscription | Platform / management subscription |
| Resource group | Platform Terraform state RG (e.g. `rg-platform-tfstate-prod`) |
| Storage account | Platform Terraform state SA (e.g. `stplatformtfstate`) |
| Container | `subvending-tfstate` |
| State key | `<archetype>/<sub-name>.tfstate` (e.g. `corp/prod-corp-erp-001.tfstate`) |
| Authentication | Microsoft Entra ID (`use_azuread_auth = true`) |
| RBAC | **Storage Blob Data Contributor** on the **container** (not the SA) |

### Why same SA, separate container

| Aspect | Same SA, dedicated container | Separate SA |
|---|---|---|
| Operational overhead | One SA to monitor / backup / firewall | Two of everything |
| Cost | Negligible | Slightly higher |
| RBAC isolation | Container-scoped role assignment is sufficient | Stronger boundary |
| Blast radius (state) | Per-blob locking is the actual boundary | Same |
| Lifecycle separation | Container ACLs + naming convention | Cleaner |

### When to split into a separate SA

- Platform team and vending team are in different orgs with separate compliance scopes
- Platform SA has private-endpoint / network rules the vending pipeline can't traverse
- You need different soft-delete / immutability policies for vending state

Neither is typical for an early-stage ALZ. Start with a shared storage account
and dedicated container, then split later if needed.

## Bootstrap

For a Terraform starter, the recommended path is the
[`bootstrap/` Terraform module](https://github.com/haflidif/alz-sub-vending-accelerator/tree/main/bootstrap).
It creates the container, grants the UAMI `Storage Blob Data Contributor` on
the container scope, and writes the backend values to the GitHub repo as
Actions variables (`BACKEND_RESOURCE_GROUP_NAME`,
`BACKEND_STORAGE_ACCOUNT_NAME`, `BACKEND_CONTAINER_NAME`).
Bicep bootstraps skip all of these resources and variables.
See the
[bootstrap reference](https://github.com/haflidif/alz-sub-vending-accelerator/blob/main/bootstrap/README.md).

It deliberately does NOT toggle versioning / soft-delete on the platform SA —
those settings should be owned by whatever pipeline created the SA itself.

## Backend configuration

The `terraform/backend.tf` file is intentionally **partial**:

```hcl
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
```

Per-subscription state isolation is achieved at `terraform init` time:

```bash
terraform init \
  -backend-config="resource_group_name=rg-platform-tfstate-prod" \
  -backend-config="storage_account_name=stplatformtfstate" \
  -backend-config="container_name=subvending-tfstate" \
  -backend-config="key=corp/prod-corp-erp-001.tfstate" \
  -backend-config="tenant_id=$TENANT_ID" \
  -backend-config="subscription_id=$MGMT_SUB_ID"
```

GitHub Actions handles this automatically via repo variables
(`BACKEND_RESOURCE_GROUP_NAME`, `BACKEND_STORAGE_ACCOUNT_NAME`,
`BACKEND_CONTAINER_NAME`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`)
and the `state_key` produced by `discover-subs.sh`.
