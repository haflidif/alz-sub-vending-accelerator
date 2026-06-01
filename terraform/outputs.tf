output "subscription_id" {
  description = "ID of the vended subscription."
  value       = module.subscription.subscription_id
}

output "subscription_resource_id" {
  description = "Resource ID of the subscription alias."
  value       = try(module.subscription.subscription_resource_id, null)
}

output "archetype" {
  description = "Archetype that vended this subscription."
  value       = local.archetype
}

output "alias_name" {
  description = "Subscription alias name."
  value       = local.alias_name
}

output "management_group_id" {
  description = "MG the subscription was associated with."
  value       = local.management_group_id
}

output "effective_tags" {
  description = "Final tag set applied to the subscription."
  value       = local.effective_tags
}
