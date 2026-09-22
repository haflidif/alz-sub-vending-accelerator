# Tearing down a vended subscription

This advanced operator runbook has moved to
[Retire a subscription](operators/retire-subscription.md).
Read its review warning before planning any destructive action.
The section links below preserve existing bookmarks.

<a name="when-to-use-which-path"></a>

## Choose a path

Continue to [When to use which path](operators/retire-subscription.md#when-to-use-which-path).

<a name="pre-requisites-for-any-tear-down"></a>

## Prerequisites

Continue to [Retirement prerequisites](operators/retire-subscription.md#pre-requisites-for-any-tear-down).

<a name="path-a--destroy-workload-retired-with-the-subscription"></a>

## Path A

Continue to [Destroy](operators/retire-subscription.md#path-a--destroy-workload-retired-with-the-subscription).

<a name="a1--run-terraform-destroy-from-your-workstation"></a>

### Terraform destroy

Continue to [The Terraform-specific step](operators/retire-subscription.md#a1--run-terraform-destroy-from-your-workstation).

<a name="a2--cancel-the-azure-subscription"></a>

### Cancellation

Continue to [Cancel the subscription](operators/retire-subscription.md#a2--cancel-the-azure-subscription).

<a name="a3--remove-the-yaml-and-clean-the-state-blob"></a>

### Request and state cleanup

Continue to [Remove the YAML and clean the state blob](operators/retire-subscription.md#a3--remove-the-yaml-and-clean-the-state-blob).

<a name="path-b--cancel-then-archive-workload-data-must-outlive-the-sub"></a>

## Path B

Continue to [Cancel then archive](operators/retire-subscription.md#path-b--cancel-then-archive-workload-data-must-outlive-the-sub).

<a name="path-c--detach-keep-the-subscription-stop-managing-it"></a>

## Path C

Continue to [Detach](operators/retire-subscription.md#path-c--detach-keep-the-subscription-stop-managing-it).

<a name="validation-after-tear-down"></a>

## Validation

Continue to [Validation after retirement](operators/retire-subscription.md#validation-after-tear-down).

<a name="what-about-the-pipeline-uami--state-container--github-repo"></a>

## Platform resources

Continue to [Platform-level resources](operators/retire-subscription.md#what-about-the-pipeline-uami--state-container--github-repo).

[Documentation index](README.md)
