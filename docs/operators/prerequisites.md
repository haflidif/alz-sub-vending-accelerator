# Prerequisites

[Documentation](../README.md) | Previous: [Planning](planning.md) | Next: [Bootstrap](bootstrap.md)

**Audience:** platform operators. Verify these requirements from the
workstation where you will run bootstrap. Consumers using an existing
vending repository start with [their first subscription](../consumers/first-subscription.md).

## Tools

Both engines use the same Terraform-based bootstrap. Make these tools
available in your PowerShell terminal:

| Tool | Required version | Verify |
|---|---|---|
| PowerShell | 7.2 or newer | `$PSVersionTable.PSVersion` |
| Terraform | `>= 1.10.0` and `< 2.0.0` | `terraform version` |
| Azure CLI | 2.64.0 or newer | `az version` |
| GitHub CLI | 2.50.0 or newer | `gh version` |

Obtain an [accelerator source checkout][source] containing `bootstrap/`,
`powershell/`, and `starters/`. These folders are not shipped to generated
vending repositories. You also need access to download Terraform providers
and reach Azure and GitHub APIs.

## Azure resources and access

| Requirement | Verify |
|---|---|
| Existing ALZ-compatible root management group and child groups for your archetypes | `az account management-group list -o table` |
| Platform/management subscription in the intended tenant | `az account show` |
| Terraform runtime only: an existing state storage account with Entra ID authentication | `az storage account list --subscription <mgmt-sub> -o table`; see [State storage](../state-storage.md) |
| Billing scope IDs and a person authorized to grant subscription-creation permissions | Use the agreement-specific [discovery and permission guidance](../billing-scopes.md) |
| Optional hub VNet when requests use hub peering | `az network vnet show --ids <id>` |
| Azure CLI signed into the platform tenant, with rights to create the pipeline identity and assign roles at the required scopes | `az account show`; check the resource and permission inventory in the [bootstrap reference][bootstrap-reference] |
| Terraform runtime only: permission to create the vending state container | Confirm access to the selected storage account |

In a green-field test tenant, first establish the management-group hierarchy
and platform subscription. Add a state storage account for Terraform.
Existing compatible platforms do not need to be redeployed.

Billing permissions are separate from Azure resource RBAC. The pipeline
identity receives its billing-role grant after creation during
[Bootstrap](bootstrap.md#step-2-grant-subscriptioncreator-on-the-billing-scope).
Check the [agreement verification status](../billing-scopes.md#subscriptioncreator-role-grant-one-off-per-scope)
before assuming your billing arrangement has been tenant-verified.

If you plan to request the `DevTest` offer, confirm
[the billing entitlement](bootstrap.md#devtest-entitlement-optional).
It is not required for the default `Production` offer.

## GitHub access

Confirm the GitHub owner and repository settings, authenticate with `gh auth
login`, and inspect `gh auth status`. Bootstrap resolves a token from
`GITHUB_TOKEN` or the authenticated GitHub CLI.

The bootstrap reference lists `repo` and, for organization repository creation,
`admin:org` access. Workflow file seeding also requires `workflow` scope for
the classic token path. See the [wizard's token troubleshooting](../bootstrap-wizard.md#troubleshooting).
Do not store tokens in request files or committed configuration.

Identify CODEOWNERS and production reviewers before continuing. The wizard
checks reviewer eligibility and warns about one-person approval limitations.
See [the approval guidance](../../.github/CICD.md#troubleshooting).

## Ready to continue

Your tools run, the platform resources exist, and the responsible operators
can supply Azure, billing, and GitHub access. Continue to
[Bootstrap](bootstrap.md) from the accelerator source checkout.

[source]: https://github.com/haflidif/alz-sub-vending-accelerator
[bootstrap-reference]: https://github.com/haflidif/alz-sub-vending-accelerator/blob/main/bootstrap/README.md
