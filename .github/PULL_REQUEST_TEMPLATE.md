<!--
Thanks for contributing! Fill in the relevant sections below.
The schema-validation and plan jobs will run automatically.
-->

## Summary

<!-- One or two sentences. What does this PR change? -->

## Type of change

- [ ] New subscription (added a YAML under `landingzones/<archetype>/`)
- [ ] Modified existing subscription (changed an existing YAML)
- [ ] Removed subscription (deleted a YAML — note: this does not delete the Azure sub)
- [ ] Skeleton change (Terraform, workflows, scripts, schema, docs)
- [ ] Other (describe)

## Subscription change checklist

If this PR adds or modifies a `landingzones/<archetype>/*.yaml` file:

- [ ] File path matches the archetype name (`landingzones/corp/*.yaml`, `landingzones/online/*.yaml`, `landingzones/sandbox/*.yaml`)
- [ ] `archetype` matches the folder name (`corp` / `online` / `sandbox`)
- [ ] `aliasName` follows `<env>-<archetype>-<workload>-<###>` and is unique
- [ ] `workload` is set (`Production` or `DevTest`)
- [ ] `owner` is set (business-owner email, required by schema)
- [ ] For sandbox: `budget.amount` is set (schema-required)
- [ ] Tags do not collide with reserved keys (see `docs/tagging.md`)
- [ ] Reviewed the **PR plan output** in Actions before requesting review

## Skeleton change checklist

If this PR modifies anything outside `landingzones/`:

- [ ] No tenant-specific or environment-specific values in code, defaults, or docs
- [ ] `terraform fmt` / `terraform validate` clean
- [ ] Schema (`landingzones/sub.schema.json`) updated if new YAML fields were added
- [ ] Docs in `docs/` updated to match behaviour change
- [ ] No new required variable without a sensible default or doc update

## Linked issues

<!-- e.g. Closes #123 -->
