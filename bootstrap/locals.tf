# =============================================================================
# Bootstrap-side derivations
# =============================================================================
# Resolves each entry in var.billing_scopes into the full Azure billing scope
# path string consumed by AVM/avm-ptn-alz-sub-vending.
# =============================================================================

locals {
  resolved_billing_scopes = {
    for k, v in var.billing_scopes : k => (
      v.agreement_type == "EA" ? format(
        "/providers/Microsoft.Billing/billingAccounts/%s/enrollmentAccounts/%s",
        v.ea.billing_account_name,
        v.ea.enrollment_account_id,
        ) : v.agreement_type == "MCA" ? format(
        "/providers/Microsoft.Billing/billingAccounts/%s/billingProfiles/%s/invoiceSections/%s",
        v.mca.billing_account_name,
        v.mca.billing_profile_name,
        v.mca.invoice_section_name,
        ) : format(
        "/providers/Microsoft.Billing/billingAccounts/%s/customers/%s",
        v.mpa.billing_account_name,
        v.mpa.customer_id,
      )
    )
  }
}
