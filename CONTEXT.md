# DevPod OpenCode Operator

A Kubernetes operator that watches for devpod Pods and dynamically creates a Service + HTTPRoute to expose the OpenCode instance running inside each workspace.

## Language

**Workspace**:
The unit of reconciliation — one devpod Pod, identified by the `devpod.sh/workspace-uid` label, with a derived Kubernetes resource name (`<workspace_id>-opencode`), a resolved OpenCode port (from the `devpod.sh/opencode-port` annotation or the configured default), and an owner reference back to the source Pod. The operator's reconciliation creates a Service and an HTTPRoute per Workspace.
_Avoid_: workspace resource, workspace pod, opencode workspace

**Workspace ID**:
The unique identifier for a devpod workspace, sourced from the `devpod.sh/workspace-uid` label on the Pod. Used in HTTPRoute hostnames and resource names. See also: **Workspace**.
_Avoid_: workspace UID, workspace-uid (these are the label key, not the concept)

**OpenCode**:
An interactive coding agent running inside a devpod workspace, accessible over HTTP on a configurable port (default 4096).

**DevPod**:
A Kubernetes Pod running a development workspace, identified by the label `devpod.sh/created=true`.

## Example dialogue

> **Dev:** "A new devpod came up in the devpod namespace — workspace ID `abc123`."
> **Domain expert:** "So the operator should have created a Service and HTTPRoute named `abc123-opencode`, pointing at port 4096 on the pod, with hostname `abc123.devpod.mydomain.com`."
> **Dev:** "Right. And when the pod is deleted, Kubernetes garbage-collects the Service and HTTPRoute automatically via owner references."
