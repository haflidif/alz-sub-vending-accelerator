# Upgrade a generated repository

[Documentation](../README.md) | [Run](run.md)

> **Preview first:** Run the command without `-Apply`. The preview does not
> change files, create a branch, or open a pull request.

```powershell
pwsh ./scripts/Update-SubscriptionVending.ps1 -TargetVersion v0.3.0
```

Use this runbook to upgrade accelerator-managed files in an established
generated vending repository. Run the command from the generated repository,
not from the accelerator source used for bootstrap.

---

## Understand the upgrade boundary

Bootstrap creates the repository and records the initial accelerator version,
selected starter, and hashes of the managed files. After handoff, the generated
repository owns its source. Do not rerun bootstrap to deliver upgrades.

The upgrade command manages accelerator-supplied:

- GitHub workflows and discovery scripts
- Shared documentation and helper scripts
- The subscription request schema
- Root guidance and release metadata
- The selected Terraform or Bicep engine implementation

The command does not manage:

- `landingzones/<archetype>/*.yaml` subscription requests
- `terraform/terraform.auto.tfvars`
- `bicep/platform.json`
- `.github/CODEOWNERS`
- Locally added files
- Secrets, repository variables, identities, settings, or bootstrap state

The exact boundary is declared in `upgrade-manifest.json`.

## Prepare the repository

Before previewing an upgrade:

1. Finish or commit current work so the working tree is clean.
2. Fetch the latest remote changes.
3. Identify the target accelerator release.
4. Read its release notes and migration guidance.
5. Test production-impacting upgrades in a non-production environment first.

Use an explicit version for reproducible upgrades:

```powershell
pwsh ./scripts/Update-SubscriptionVending.ps1 -TargetVersion v0.3.0
```

Use `-Latest` only when you intentionally want the latest published GitHub
release:

```powershell
pwsh ./scripts/Update-SubscriptionVending.ps1 -Latest
```

## Review the preview

The command reports each planned operation:

```text
[ADD] path/to/new-file
[UPDATE] path/to/changed-file
[REMOVE] path/to/removed-file
[CONFLICT] path/to/customized-file: Locally modified managed file
```

The comparison uses text hashes recorded at bootstrap or the previous upgrade.
Line endings are normalized so Windows and Unix checkouts produce the same
baseline. A local customization is allowed when the target release does not
change that managed file. If both the repository and the target release
changed the file, the command reports a conflict.

Conflict detection is atomic. If any conflict exists, the command changes no
files and creates no branch.

## Resolve conflicts

For each conflict, decide whether the file should remain locally customized or
return to accelerator ownership.

To keep the customization:

1. Compare the current file with the current and target accelerator versions.
2. Port the required upstream changes into the local file manually.
3. Keep the file outside the automatic upgrade for this attempt.
4. Record the ownership decision in the upgrade pull request.

To return to accelerator ownership:

1. Restore the file to the content recorded by the current baseline.
2. Commit that restoration separately.
3. Run the upgrade preview again.

Do not delete metadata or edit hashes to bypass a conflict. That removes the
evidence needed to determine whether an overwrite is safe.

## Apply the upgrade

After reviewing a conflict-free preview, create the versioned upgrade branch
and update the working tree:

```powershell
pwsh ./scripts/Update-SubscriptionVending.ps1 `
  -TargetVersion v0.3.0 `
  -Apply
```

The default branch is `upgrade/accelerator-<version>`. The command updates
`.accelerator/metadata.json` with the target version and new managed-file
hashes.

Inspect the working tree before committing:

```powershell
git status --short
git diff
```

You can ask the command to commit, push, and open the pull request:

```powershell
pwsh ./scripts/Update-SubscriptionVending.ps1 `
  -TargetVersion v0.3.0 `
  -Apply `
  -CreatePullRequest
```

This option requires authenticated `git` and GitHub CLI access. It does not
merge the pull request or deploy subscriptions.

## Review and merge

The upgrade pull request uses the normal repository controls:

1. Review all managed-file changes and release notes.
2. Confirm that repository-owned files remain unchanged.
3. Review the full Terraform plan or Bicep what-if across all requests.
4. Resolve required reviews and status checks.
5. Merge through the normal protected-branch process.

Merging an upgrade does not automatically deploy the shared change. The Apply
workflow reports that an explicit fleet deployment is required.

When you are ready to deploy the reviewed upgrade:

1. Open **Actions > Apply > Run workflow**.
2. Select `mode=all`.
3. Review and approve the production environment gate.
4. Confirm the result for every subscription.

## Adopt an older generated repository

Repositories created before `.accelerator/metadata.json` do not contain the
updater or a managed-file baseline. Check out the target accelerator release,
then run its updater against the generated repository:

```powershell
pwsh <accelerator-checkout>/scripts/Update-SubscriptionVending.ps1 `
  -RepositoryRoot <generated-repository-path> `
  -CurrentVersion v0.2.0 `
  -Starter terraform `
  -TargetVersion v0.3.0 `
  -Apply
```

Use `bicep` instead of `terraform` for a Bicep repository. The command compares
the generated repository with the explicitly supplied current release, then
creates metadata containing the target release hashes.

Verify that `-CurrentVersion` identifies the release originally used to create
the repository. If the repository was seeded from an untagged commit or has
unknown provenance, perform a manual comparison before adoption.

## Handle common outcomes

| Outcome | Action |
| --- | --- |
| The repository already records the target version | No upgrade is required |
| No managed files changed between releases | The command exits successfully without creating a branch or pull request |
| The working tree is not clean | Commit or discard unrelated work, then rerun |
| A managed file conflicts | Resolve the ownership decision, then rerun the preview |
| A new managed path collides with a local file | Rename or deliberately reconcile the local file before upgrading |
| The target release cannot be downloaded | Verify the tag, repository access, network access, and GitHub availability |
| Pull request creation fails | Keep the local upgrade branch and create the pull request manually |

## Related guidance

- [Run the vending service](run.md)
- [CI/CD triggers and explicit deployment](../../.github/CICD.md)
- [Repository layout and ownership](../repository-layout.md)
- [Upgrade command reference](../../scripts/README.md#update-subscriptionvendingps1)
- [Release history](../../CHANGELOG.md)
