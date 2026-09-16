# Billing scopes

Both vending engines require a single billing scope path per subscription
they create. This skeleton lets you declare **one or more** billing scopes,
initially at bootstrap time and later by PR to the seeded repository. Each
request selects one through `billingScopeKey:`.

> **Path strings are case-sensitive end-to-end.** Use the discovery commands
> below to copy the canonical form.

> **Day-2 changes go to the seeded repo.** The bootstrap is one-shot. To add,
> remove, or rotate a billing scope after the initial bootstrap, edit the
> selected engine configuration directly via PR:
> `terraform/terraform.auto.tfvars` (`billing_scopes`) or
> `bicep/platform.json` (`billingScopes`). See
> [`docs/onboarding.md` → "Updating platform inputs after bootstrap"](onboarding.md#updating-platform-inputs-after-bootstrap).

---

## Supported agreement types

| Agreement type           | Path format                                                                                                                |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| **EA** (Enterprise)      | `/providers/Microsoft.Billing/billingAccounts/{enrollmentNumber}/enrollmentAccounts/{accountId}`                           |
| **MCA** (Customer)       | `/providers/Microsoft.Billing/billingAccounts/{name}/billingProfiles/{profile}/invoiceSections/{section}`                 |
| **MPA** (Partner CSP)    | `/providers/Microsoft.Billing/billingAccounts/{name}/customers/{customerId}`                                              |

* EA `{accountId}` is the **enrollment account**, not the EA department. Departments are NOT addressable in the path; they exist only in EA reporting.
* MCA `{name}` is a composite GUID (`{billingAccountId}:{billingProfileId}_yyyy-mm-dd`).
* MPA — the partner must have already provisioned the customer tenant; the principal needs the *Indirect Buyer* / *Indirect Provisioner* role on the customer scope.

---

## Bootstrap input (initial seed)

Declared in `bootstrap/terraform.tfvars` for the **first** apply only. The
bootstrap derives the canonical path string and writes the resolved map into
the selected engine configuration. After bootstrap, edit that rendered file
directly in the seeded repository via PR to add or change scopes.

```hcl
billing_scopes = {
  default = {
    agreement_type = "MCA"
    mca = {
      billing_account_name = "11111111-2222-3333-4444-555555555555:66666666-7777-8888-9999-000000000000_2024-01-31"
      billing_profile_name = "ABCD-EFGH-IJK-LMN"
      invoice_section_name = "WXYZ-1234"
    }
  }
  sandbox = {
    agreement_type = "EA"
    ea = {
      billing_account_name  = "7690848"
      enrollment_account_id = "403507"
    }
  }
  customer-acme = {
    agreement_type = "MPA"
    mpa = {
      billing_account_name = "abcdef-1234"
      customer_id          = "00000000-0000-0000-0000-000000000000"
    }
  }
}
```

* The map MUST contain a `default` entry — used when a `sub.yaml` omits `billingScopeKey`.
* Add as many additional named entries as you need. Common patterns: `sandbox`, `dev`, `customer-<name>`, `prod-mca-corp`, `prod-mca-online`.
* Per entry: set `agreement_type` and populate exactly the matching nested object (`ea` / `mca` / `mpa`).

### Per-sub override

```yaml
# landingzones/sandbox/dev-sandbox-platform-001.yaml
billingScopeKey: sandbox
```

If omitted, `default` is used.

---

## Discovery commands

### EA — list enrollment accounts

```bash
az billing account list --query "[?agreementType=='EnterpriseAgreement'].{name:name,displayName:displayName}" -o table
az billing enrollment-account list --account-name <enrollmentNumber> -o table
```

### MCA — drill from billing account → profile → invoice section

```bash
az billing account list --query "[?agreementType=='MicrosoftCustomerAgreement'].{name:name,displayName:displayName}" -o table
az billing profile list --account-name <name> -o table
az billing invoice-section list --account-name <name> --profile-name <profile> -o table
```

### MPA — list partner billing accounts and customers

```bash
az billing account list --query "[?agreementType=='MicrosoftPartnerAgreement'].{name:name,displayName:displayName}" -o table
az billing customer list --account-name <name> -o table
```

### Portal navigation

* **EA**: *Cost Management + Billing* → *Billing scopes* → select EA → *Enrollment accounts*.
* **MCA**: *Cost Management + Billing* → *Billing profiles* → *Invoice sections*.
* **MPA**: *Partner Center* → *Customers* → copy the customer tenant ID.

---

## SubscriptionCreator role grant (one-off, per scope)

After running the bootstrap, a privileged operator (EA admin / MCA Billing
Profile Owner / Partner Admin) must grant the pipeline UAMI permission to
**create subscriptions** under each billing scope. The bootstrap output
`next_step_billing_role` prints the exact PowerShell commands.

```powershell
Install-Module ALZ -Scope CurrentUser
Import-Module ALZ

# EA example
Grant-SubscriptionCreatorRole `
  -servicePrincipalObjectId '<UAMI principalId>' `
  -billingAccountID '7690848' `
  -enrollmentAccountID '403507'

# MCA example
Grant-SubscriptionCreatorRole `
  -servicePrincipalObjectId '<UAMI principalId>' `
  -billingAccountID '<MCA billing account name>' `
  -billingProfileID '<billing profile>' `
  -invoiceSectionID '<invoice section>'
```

---

## Gotchas

| Symptom                                                                         | Likely cause                                                                                                                |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `415 Unsupported Media Type` from `Grant-SubscriptionCreatorRole`              | Known issue when the ALZ module signs the request. Fall back to `az rest --method PUT` against `/billingRoleAssignments/...` (see docs/onboarding.md). |
| `EnrollmentAccountOwnerNotFound`                                                | The principal granting the role isn't the EA enrollment account owner. Check `az billing enrollment-account show ... --query principalName`.  |
| MCA `400 Bad Request` on create                                                | Wrong invoice-section permissions — the UAMI needs *Azure subscription creator* on the invoice section, not just the billing profile.       |
| MPA create fails silently                                                       | Partner needs *Indirect Buyer* + *Admin agent* roles on the customer tenant.                                                                |
| `billingScopeKey 'foo' not found`                                               | The key does not exist in `terraform/terraform.auto.tfvars` or `bicep/platform.json`. Add it to the selected engine configuration via PR. |

---

## See also

* [docs/onboarding.md](onboarding.md) — full operator onboarding flow
* [docs/tagging.md](tagging.md) — cost-allocation tag configuration
* [Terraform AVM module: `subscription_billing_scope`](https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest)
* [Bicep AVM subscription-vending pattern](https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/lz/sub-vending)
* [Azure billing — billing account API](https://learn.microsoft.com/rest/api/billing/2020-05-01/billing-accounts)
