###############################################################################
# Identity & state location
###############################################################################

variable "starter_name" {
  type        = string
  default     = "terraform"
  description = "Starter package selected by the PowerShell accelerator."

  validation {
    condition     = contains(["terraform", "bicep"], var.starter_name)
    error_message = "starter_name must be either terraform or bicep."
  }
}

variable "platform_subscription_id" {
  type        = string
  description = "Subscription that owns the platform Terraform state SA and the pipeline UAMI."
}

variable "uami_resource_group_name" {
  type        = string
  description = "Resource group that will hold the pipeline UAMI. Must already exist."
}

variable "uami_name" {
  type        = string
  default     = "id-subvending-pipeline"
  description = "Name of the User-Assigned Managed Identity used by the pipeline."
}

variable "location" {
  type        = string
  description = "Azure region for the UAMI (state SA location is unchanged)."
}

###############################################################################
# State backend (existing platform storage account)
###############################################################################

variable "state_storage_account_resource_group_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Resource group of the existing platform storage account used by the Terraform starter. Not used by Bicep."

  validation {
    condition     = var.starter_name != "terraform" || (var.state_storage_account_resource_group_name != null && var.state_storage_account_resource_group_name != "")
    error_message = "state_storage_account_resource_group_name is required for the Terraform starter."
  }
}

variable "state_storage_account_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Name of the existing platform storage account used by the Terraform starter. Not used by Bicep."

  validation {
    condition     = var.starter_name != "terraform" || (var.state_storage_account_name != null && var.state_storage_account_name != "")
    error_message = "state_storage_account_name is required for the Terraform starter."
  }
}

variable "state_container_name" {
  type        = string
  default     = "subvending-tfstate"
  description = <<-EOT
    Container created for per-subscription Terraform state when starter_name is terraform.
    The Bicep starter does not create or use this container.
    Default mirrors the ALZ Accelerator's `<name>-tfstate` naming style. If your
    platform team prefers an environment-prefixed name (e.g. `core-subvending-tfstate`
    when `environment_name = "core"` in the accelerator inputs), override here.
  EOT
}

###############################################################################
# Azure RBAC scopes
###############################################################################

variable "alz_root_management_group_id" {
  type        = string
  description = <<-EOT
    Bare management-group name (NOT a full resource ID) at or above the archetype
    MGs (corp / online / sandbox / extra). The pipeline UAMI receives
    `Contributor` (and optionally `User Access Administrator`)
    here, and inheritance covers every archetype MG below.

    PRECONDITION: this MG MUST be a parent of every archetype MG listed in
    `management_group_ids`. If your archetypes live under different parents,
    either pick a higher common ancestor or fork bootstrap to loop the role
    assignments per-MG.
  EOT
}

variable "connectivity_subscription_id" {
  type        = string
  description = "Connectivity (hub) subscription ID. Used to scope Network Contributor for hub VNet peering. When `hub_virtual_network_resource_id` is set, the role is RG-scoped (least privilege); otherwise sub-scoped as a fallback."
}

variable "grant_user_access_administrator" {
  type        = bool
  default     = true
  description = "Grant UAA on the MG scope. Required when sub YAML files declare roleAssignments."
}

###############################################################################
# GitHub repository
###############################################################################

variable "github_owner" {
  type        = string
  description = "GitHub org or user that owns the repo (e.g. 'your-github-org')."
}

variable "github_repository_name" {
  type        = string
  default     = "sub-vending"
  description = "Repository name."
}

variable "create_github_repository" {
  type        = bool
  default     = false
  description = "If true, the repo is created. If false, it must already exist."
}

variable "github_repository_visibility" {
  type        = string
  default     = "private"
  description = "private | internal | public — only used when create_github_repository = true."
}

variable "github_default_branch" {
  type        = string
  default     = "main"
  description = "Default branch — used in OIDC subject claims."
}

variable "github_oidc_subject_mode" {
  type        = string
  default     = "standard"
  description = "GitHub OIDC subject format: standard or immutable."

  validation {
    condition     = contains(["standard", "immutable"], var.github_oidc_subject_mode)
    error_message = "github_oidc_subject_mode must be standard or immutable."
  }
}

variable "github_owner_id" {
  type        = number
  default     = null
  nullable    = true
  description = "Numeric GitHub organization or user ID. Required for immutable OIDC subjects."

  validation {
    condition     = var.github_oidc_subject_mode != "immutable" || var.github_owner_id != null
    error_message = "github_owner_id is required when github_oidc_subject_mode is immutable."
  }
}

###############################################################################
# Branch protection on the default branch
###############################################################################

variable "enforce_branch_protection" {
  type        = bool
  default     = true
  description = "If true, applies a github_branch_protection rule to the default branch (requires PR + passing status checks)."
}

variable "branch_protection_required_status_checks" {
  type        = list(string)
  default     = ["PR Validate / YAML schema validation", "PR Validate / PR Validate Result"]
  description = "Workflow check contexts that must pass before merge. Defaults match `pr-validate.yml` job names — keep these in sync if you rename jobs."
}

variable "branch_protection_required_approving_review_count" {
  type        = number
  default     = 1
  description = "Number of approving reviews required before merge."
}

###############################################################################
# Production environment approvers
###############################################################################

variable "production_environment_name" {
  type        = string
  default     = "production"
  description = "Name of the GitHub Environment that gates apply."
}

variable "production_reviewer_user_ids" {
  type        = list(number)
  default     = []
  description = "GitHub user numeric IDs that must approve apply runs."
}

variable "production_reviewer_team_ids" {
  type        = list(number)
  default     = []
  description = "GitHub team numeric IDs that must approve apply runs."
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to bootstrap-created Azure resources."
}

###############################################################################
# CODEOWNERS for the seeded repo
###############################################################################

variable "codeowners_default_team" {
  type        = string
  default     = ""
  description = <<-EOT
    Default GitHub team or user that owns the seeded repo. Format: a single
    handle, e.g. '@your-org/platform-team' or '@octocat'. Applied to '*' and
    to every engine path (terraform/, bootstrap/, .github/, docs/).

    Leave empty to fall back to a placeholder '@your-org/platform-team' that
    you MUST edit post-vend. The interactive bootstrap will prompt
    you for the real value.
  EOT
  validation {
    condition     = var.codeowners_default_team == "" || can(regex("^@[A-Za-z0-9_][A-Za-z0-9_-]*(/[A-Za-z0-9_][A-Za-z0-9_-]*)?$", var.codeowners_default_team))
    error_message = "codeowners_default_team must be a single @user or @org/team handle (e.g. '@your-org/platform-team') or an empty string."
  }
}

variable "codeowners_archetype_teams" {
  type        = map(list(string))
  default     = {}
  description = <<-EOT
    Per-archetype additional reviewers, keyed by archetype name (must match a
    key in `management_group_ids`). Values are lists of GitHub team or user
    handles (e.g. ['@your-org/corp-archetype-owners']). The default team is
    always added alongside these. Archetypes with no entry inherit just the
    default team via CODEOWNERS' fall-through.
  EOT
  validation {
    condition = alltrue([
      for archetype, owners in var.codeowners_archetype_teams :
      alltrue([for o in owners : can(regex("^@[A-Za-z0-9_][A-Za-z0-9_-]*(/[A-Za-z0-9_][A-Za-z0-9_-]*)?$", o))])
    ])
    error_message = "Every value in codeowners_archetype_teams must be a list of @user or @org/team handles."
  }
}

###############################################################################
# Platform context — written into a `terraform/terraform.auto.tfvars` in the
# seeded repo so the workflows can `terraform plan` without manual setup.
# These values are static per tenant/platform LZ — set them once at bootstrap
# time. Per-subscription values come from each `landingzones/<arch>/*.yaml`.
###############################################################################

variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant ID. Written into terraform.auto.tfvars in the seeded repo."
}

variable "billing_scopes" {
  type = map(object({
    agreement_type = string
    ea = optional(object({
      enrollment_account_id = string
      billing_account_name  = string
    }))
    mca = optional(object({
      billing_account_name = string
      billing_profile_name = string
      invoice_section_name = string
    }))
    mpa = optional(object({
      billing_account_name = string
      customer_id          = string
    }))
  }))
  description = <<-EOT
    Billing scopes available to vended subscriptions, keyed by name. The map
    MUST contain a `default` entry. Per-sub YAML files can opt into a
    non-default key via `billingScopeKey: <name>`.

    Each entry sets `agreement_type` to one of EA | MCA | MPA and populates
    the matching nested object. The bootstrap derives the full Azure billing
    scope path string and writes the resolved map into the seeded repo's
    terraform.auto.tfvars. See docs/billing-scopes.md for path formats and
    discovery commands.

    Example:
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
      }
  EOT

  validation {
    condition     = contains(keys(var.billing_scopes), "default")
    error_message = "billing_scopes must contain a 'default' entry."
  }
  validation {
    condition = alltrue([
      for k, v in var.billing_scopes : contains(["EA", "MCA", "MPA"], v.agreement_type)
    ])
    error_message = "Each billing_scopes entry must have agreement_type in {EA, MCA, MPA}."
  }
  validation {
    condition = alltrue([
      for k, v in var.billing_scopes : (
        (v.agreement_type == "EA" && v.ea != null && v.mca == null && v.mpa == null) ||
        (v.agreement_type == "MCA" && v.mca != null && v.ea == null && v.mpa == null) ||
        (v.agreement_type == "MPA" && v.mpa != null && v.ea == null && v.mca == null)
      )
    ])
    error_message = "For each billing_scopes entry, populate exactly the nested object matching agreement_type (ea / mca / mpa) and leave the others null."
  }
}

variable "cost_allocation_tag" {
  type = object({
    name     = optional(string, "projectcode")
    required = optional(bool, false)
    pattern  = optional(string)
  })
  default     = {}
  description = <<-EOT
    Operator-configurable cost-allocation tag emitted IN ADDITION to the
    always-on `costcenter` tag. Set `name` to your organization's convention
    (e.g. activitycode, wbselement, programcode). Set `required = true` to
    fail-fast when a sub.yaml omits `costAllocationCode`. Optional `pattern`
    is a Terraform regex (anchors recommended) validated at plan time.
    Written into the seeded repo's terraform.auto.tfvars.
  EOT

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,127}$", coalesce(var.cost_allocation_tag.name, "projectcode")))
    error_message = "cost_allocation_tag.name must be lowercase alphanumeric, 2-128 chars, starting with a letter (CAF tag convention)."
  }
}

variable "management_group_ids" {
  type        = map(string)
  description = <<-EOT
    Map of archetype name -> destination management group ID.
    Keys MUST match the archetype values used in landingzones/<archetype>/*.yaml
    (corp / online / sandbox by default). Written into terraform.auto.tfvars
    in the seeded repo.
  EOT
}

variable "hub_virtual_network_resource_id" {
  type        = string
  default     = ""
  description = "Resource ID of the platform hub VNet to peer corp/online subscriptions to. Leave empty if no hub. Written into terraform.auto.tfvars in the seeded repo."
}

variable "hub_virtual_network_use_remote_gateways" {
  type        = bool
  default     = false
  description = "Whether Bicep spoke peerings use a virtual network gateway in the configured hub. Keep false unless the hub has a gateway configured for transit."
}

variable "mandatory_tags" {
  type = map(string)
  default = {
    managedby  = "terraform"
    source     = "avm-ptn-alz-sub-vending"
    deployedby = "subscription-vending-pipeline"
  }
  description = <<-EOT
    Platform-wide tags merged into every vended subscription. CAF-aligned
    defaults (lowercase, no separators). Written into the seeded repo's
    terraform.auto.tfvars. Per-subscription identity tags
    (businessowner / costcenter / etc.) layer on top.
  EOT
}

###############################################################################
# Skeleton seeding
###############################################################################

variable "copy_skeleton_files" {
  type        = bool
  default     = true
  description = "If true, push every file in skeleton_source_path (excluding bootstrap/, .terraform/, etc.) into the target repo as github_repository_file resources. Set to false after the initial seed if you do not want Terraform to keep managing them."
}

variable "skeleton_source_path" {
  type        = string
  default     = ".."
  description = "Path (relative to bootstrap/) of the directory whose contents seed the target repo. Default '..' means the parent of bootstrap/, i.e. this repo. Override only if running from outside the skeleton checkout."
}

variable "skeleton_commit_author" {
  type        = string
  default     = "sub-vending-bootstrap"
  description = "Git author name used for the seed commits."
}

variable "skeleton_commit_email" {
  type        = string
  default     = "platform-bootstrap@example.local"
  description = "Git author email used for the seed commits."
}


###############################################################################
# Sentinel set by bootstrap/Invoke-Bootstrap.ps1 wizard
###############################################################################

variable "managed_by_invoke_bootstrap" {
  type        = bool
  default     = false
  description = <<-EOT
    Sentinel that the bootstrap wizard writes into terraform.tfvars.json so
    re-runs can detect whether the file was rendered by the wizard or
    hand-edited. Has no effect on any resource. Safe to ignore.
  EOT
}