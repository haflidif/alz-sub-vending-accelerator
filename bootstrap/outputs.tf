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
  description = "Object ID of the UAMI. Use this for the manual Grant-SubscriptionCreatorRole step."
}

output "uami_resource_id" {
  value       = azurerm_user_assigned_identity.pipeline.id
  description = "Full Azure resource ID of the UAMI."
}

output "state_container_name" {
  value       = azurerm_storage_container.tfstate.name
  description = "Created Terraform state container (in the platform storage account)."
}

output "github_repository_full_name" {
  value       = "${var.github_owner}/${local.github_repo_name}"
  description = "Configured GitHub repository."
}

output "next_step_billing_role" {
  value = join("\n", concat(
    [
      "Manual follow-up — grant SubscriptionCreator on EACH billing scope:",
      "",
      "  Install-Module ALZ -Scope CurrentUser",
      "  Import-Module ALZ",
      "",
    ],
    flatten([
      for k, v in var.billing_scopes : (
        v.agreement_type == "EA" ? [
          "  # billing_scopes[\"${k}\"] (EA)",
          "  Grant-SubscriptionCreatorRole `",
          "    -servicePrincipalObjectId '${azurerm_user_assigned_identity.pipeline.principal_id}' `",
          "    -billingAccountID '${v.ea.billing_account_name}' `",
          "    -enrollmentAccountID '${v.ea.enrollment_account_id}'",
          "",
          ] : v.agreement_type == "MCA" ? [
          "  # billing_scopes[\"${k}\"] (MCA)",
          "  Grant-SubscriptionCreatorRole `",
          "    -servicePrincipalObjectId '${azurerm_user_assigned_identity.pipeline.principal_id}' `",
          "    -billingAccountID '${v.mca.billing_account_name}' `",
          "    -billingProfileID '${v.mca.billing_profile_name}' `",
          "    -invoiceSectionID '${v.mca.invoice_section_name}'",
          "",
          ] : [
          "  # billing_scopes[\"${k}\"] (MPA — assign Indirect Buyer / Indirect Provisioner role on customer)",
          "  # az role assignment create --role 'Azure subscription creator' --assignee-object-id '${azurerm_user_assigned_identity.pipeline.principal_id}' --scope '/providers/Microsoft.Billing/billingAccounts/${v.mpa.billing_account_name}/customers/${v.mpa.customer_id}'",
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
  description = "Reminder for the one step that cannot be done in Terraform — runs once per billing scope."
}
