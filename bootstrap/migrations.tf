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

# Preserve source-file addresses while introducing the post-bootstrap handoff
# gate. The wizard detaches these resources after the upgraded apply succeeds.
moved {
  from = github_repository_file.accelerator_metadata
  to   = github_repository_file.accelerator_metadata[0]
}

moved {
  from = github_repository_file.codeowners
  to   = github_repository_file.codeowners[0]
}
