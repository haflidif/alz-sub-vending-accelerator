# Preserve existing Terraform bootstrap state addresses after making runtime
# state resources conditional on the selected starter.
moved {
  from = azurerm_storage_container.tfstate
  to   = azurerm_storage_container.tfstate[0]
}

moved {
  from = azurerm_role_assignment.state_blob_contributor
  to   = azurerm_role_assignment.state_blob_contributor[0]
}

moved {
  from = github_actions_variable.backend_resource_group
  to   = github_actions_variable.backend_resource_group[0]
}

moved {
  from = github_actions_variable.backend_storage_account
  to   = github_actions_variable.backend_storage_account[0]
}

moved {
  from = github_actions_variable.backend_container
  to   = github_actions_variable.backend_container[0]
}
