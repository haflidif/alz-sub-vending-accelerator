output "starter_name" {
  value       = var.starter_name
  description = "Starter package selected for the generated vending repository."
}

output "uami_client_id" {
  value       = azurerm_user_assigned_identity.pipeline.client_id
  description = "Pipeline UAMI client ID — also written to the AZURE_CLIENT_ID repo variable."
}

output "uami_principal_id" {
  value       = azurerm_user_assigned_identity.pipeline.principal_id
  description = "Object ID of the UAMI. Use this with scripts/Grant-SubscriptionCreatorRole.ps1."
}

output "uami_resource_id" {
  value       = azurerm_user_assigned_identity.pipeline.id
  description = "Full Azure resource ID of the UAMI."
}

output "state_container_name" {
  value       = try(azurerm_storage_container.tfstate[0].name, null)
  description = "Created Terraform runtime state container, or null for the Bicep starter."
}

output "github_repository_full_name" {
  value       = "${var.github_owner}/${local.github_repo_name}"
  description = "Configured GitHub repository."
}

output "bootstrap_seed_pull_request_url" {
  value       = try("https://github.com/${var.github_owner}/${local.github_repo_name}/pull/${github_repository_pull_request.bootstrap_seed[0].number}", null)
  description = "PR seeding/updating bootstrap-managed files, opened because enforce_branch_protection = true blocks direct commits. Null when branch protection is off (files were pushed straight to the default branch instead). Invoke-Bootstrap.ps1 waits for this to be merged."
}

output "next_step_billing_role" {
  value = join("\n", concat(
    [
      "Manual follow-up - grant SubscriptionCreator on EACH billing scope:",
      "",
    ],
    flatten([
      for k, v in var.billing_scopes : (
        v.agreement_type == "EA" ? [
          "  # billing_scopes[\"${k}\"] (EA)",
          "  pwsh ./scripts/Grant-SubscriptionCreatorRole.ps1 `",
          "    -servicePrincipalObjectId '${azurerm_user_assigned_identity.pipeline.principal_id}' `",
          "    -billingAccountID '${v.ea.billing_account_name}' `",
          "    -enrollmentAccountID '${v.ea.enrollment_account_id}'",
          "",
          ] : v.agreement_type == "MCA" ? [
          "  # billing_scopes[\"${k}\"] (MCA)",
          "  pwsh ./scripts/Grant-SubscriptionCreatorRole.ps1 `",
          "    -servicePrincipalObjectId '${azurerm_user_assigned_identity.pipeline.principal_id}' `",
          "    -billingAccountID '${v.mca.billing_account_name}' `",
          "    -billingProfileID '${v.mca.billing_profile_name}' `",
          "    -invoiceSectionID '${v.mca.invoice_section_name}'",
          "",
          ] : [
          "  # billing_scopes[\"${k}\"] (MPA - verify Partner Center permissions first)",
          "  pwsh ./scripts/Grant-SubscriptionCreatorRole.ps1 `",
          "    -servicePrincipalObjectId '${azurerm_user_assigned_identity.pipeline.principal_id}' `",
          "    -billingResourceID '/providers/Microsoft.Billing/billingAccounts/${v.mpa.billing_account_name}/customers/${v.mpa.customer_id}'",
          "",
        ]
      )
    ]),
    [
      "Resolved billing scope path strings (for reference):",
    ],
    [
      for k, v in local.resolved_billing_scopes : "  ${k} = ${v}"
    ],
  ))
  description = "Commands for the approval-gated billing role assignment that runs once per billing scope."
}
