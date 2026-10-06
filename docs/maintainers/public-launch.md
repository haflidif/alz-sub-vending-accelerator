# Public launch and repository rename

Use this runbook to rename the repository and make it public without breaking
existing generated repositories or exposing an incomplete support surface.

## Release gates

Complete each gate in order. Do not combine the repository rename and
visibility change into one step.

### 1. Merge public-readiness changes

- Publish the independent-maintainer and Microsoft support boundary in the
  README, product mandate, contribution guide, and support policy.
- Add the Code of Conduct and structured issue forms.
- Pin every GitHub Action to an immutable commit SHA.
- Limit workflow permissions and artifact retention.
- Protect `main` with reviewed pull requests and required validation.
- Configure the repository Actions allow-list and SHA-pinning requirement.
- Scan the complete Git history for credentials and sensitive data.

### 2. Rename the repository

Rename the repository to `alz-sub-vending-accelerator` while it remains
private.

After the rename:

1. Update the local remote:

   ```powershell
   git remote set-url origin https://github.com/haflidif/alz-sub-vending-accelerator.git
   git fetch origin
   ```

2. Verify the old clone URL redirects to the new repository.
3. Verify release, archive, issue, pull request, and source links redirect.
4. Verify tags and release assets remain available.
5. Run the packaging and upgrade tests.
6. Test an upgrade from metadata that records the former repository name.
7. Confirm `accelerator.json` and newly written upgrade metadata use the new
   repository name.

GitHub normally preserves redirects after a repository rename. Do not create a
new repository with the old name because doing so removes that redirect path.

### 3. Complete the final public-readiness review

- Repeat the full-history secret scan.
- Review every branch, tag, release asset, issue, pull request, Actions log,
  repository variable, environment, and deploy key for public suitability.
- Confirm examples contain no real tenant IDs, subscription IDs, billing
  identifiers, private URLs, personal data, or customer data.
- Verify the repository description, topics, homepage, and documentation use
  the final name.
- Verify anonymous documentation and release links.
- Confirm the support boundary is visible before a user reaches installation
  instructions.

### 4. Change visibility

Change the renamed repository from private to public only after the previous
gates pass.

Immediately after the visibility change:

- Enable private vulnerability reporting.
- Enable secret scanning and push protection where available.
- Enable Dependabot alerts and security updates.
- Enable Discussions and verify its support categories.
- Disable the wiki unless maintainers intentionally use it.
- Verify issue forms, the Code of Conduct, support links, branch protection,
  and Actions restrictions as an anonymous user.
- Verify the GitHub Pages site and set it as the repository homepage.

## Rollback

If the rename causes an unexpected integration failure, rename the repository
back before another repository claims the former name. Restore the local
remote, then investigate the failed integration while the repository remains
private.

If a problem appears after the visibility change, make the repository private
again to stop further casual discovery. Treat any data already exposed as
disclosed. Rotate affected credentials, remove sensitive release assets or
logs, and rewrite Git history only when the exposure requires it. A visibility
rollback does not undo prior access or cloning.

## Required evidence

Record the following evidence on the public-launch issue:

- Commit and pull request containing the readiness changes
- Successful workflow, packaging, and upgrade checks
- Full-history secret-scan result and tool version
- Repository settings snapshot
- Redirect and legacy-upgrade verification
- Anonymous access verification after publication
