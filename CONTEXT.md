# DevPod OpenCode Operator

A Kubernetes operator that watches for devpod Pods and dynamically creates a Service + HTTPRoute to expose the OpenCode instance running inside each workspace.

## Language

**Workspace**:
The unit of reconciliation — one devpod Pod, identified by the `devpod.sh/workspace-uid` label, with two distinct identifiers: a `uid` (the 16-char devpod UID, e.g. `default-po-3e6db`, from the `devpod.sh/workspace-uid` label) and an `id` (the human-friendly workspace name, e.g. `po`, from the `DEVPOD_WORKSPACE_ID` env var on the devpod container, falling back to the uid). The K8s resource name (`<uid>-opencode`) and HTTPRoute hostname (`<uid>.<base_domain>`) both use the uid for stability. The friendly id is carried on the `devpod.sh/workspace` label for display purposes (e.g. by the Portal). The operator's reconciliation creates a Service and an HTTPRoute per Workspace.
_Avoid_: workspace resource, workspace pod, opencode workspace

**Workspace ID**:
The unique identifier for a devpod workspace, sourced from the `devpod.sh/workspace-uid` label on the Pod. Used in HTTPRoute hostnames. See also: **Workspace**.
_Avoid_: workspace UID, workspace-uid (these are the label key, not the concept)

**OpenCode**:
An interactive coding agent running inside a devpod workspace, accessible over HTTP on a configurable port (default 4096).

**OpenCode Endpoint**:
The user-facing URL `https://<workspace_id>.<base_domain>` backed by an operator-owned HTTPRoute. Its existence is what makes a Workspace "available" from the portal's perspective. The portal discovers endpoints by listing HTTPRoutes labelled `app.kubernetes.io/managed-by: devpod-opencode-operator`.
_Avoid_: workspace link, workspace URL, opencode URL

**DevPod**:
A Kubernetes Pod running a development workspace, identified by the label `devpod.sh/created=true`.

## Example dialogue

> **Dev:** "A new devpod came up in the devpod namespace — workspace id `po`, uid `default-po-3e6db`."
> **Domain expert:** "So the operator should have created a Service and HTTPRoute named `default-po-3e6db-opencode`, with hostname `default-po-3e6db.devpod.mydomain.com`. The Portal shows `po` as the friendly display name."
> **Dev:** "Right. And when the pod is deleted, Kubernetes garbage-collects the Service and HTTPRoute automatically via owner references."

**Owner Reference**:
The `ownerReferences` field set on the Service and HTTPRoute metadata, pointing back to the source Pod. Computed from the Pod's K8s metadata (`apiVersion`, `kind`, `name`, `uid`) via `Workspace.build_owner_reference/1`. When the Pod has no K8s metadata UID (e.g. during test setup), `owner_reference` is `nil` and `ownerReferences` is omitted from the manifests entirely.
