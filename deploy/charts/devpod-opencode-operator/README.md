# devpod-opencode-operator Helm Chart

A Kubernetes operator that watches for [DevPod](https://devpod.sh) workspace Pods and dynamically creates **Service** + **HTTPRoute** (`gateway.networking.k8s.io`) resources to expose OpenCode instances running inside each workspace.

## Prerequisites

| Requirement | Version |
|---|---|
| Kubernetes | >= 1.24 |
| Helm | >= 3.10 |
| Gateway API CRDs | installed on the cluster |

## Installing the Chart

```bash
helm install devpod-opencode-operator ./deploy/charts/devpod-opencode-operator \
  --namespace devpod-system \
  --create-namespace \
  --set operator.baseDomain=my.domain.com \
  --set operator.gatewayName=main-gateway \
  --set operator.gatewayNamespace=gateway-system
```

## Configuration

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `1` | Number of operator replicas. |
| `image.repository` | `ghcr.io/TomGrozev/devpod-opencode-operator` | Container image. |
| `image.tag` | `""` (appVersion) | Image tag. |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `leaderElection.enabled` | `true` | Enable leader election for HA. |
| `serviceAccount.create` | `true` | Create a ServiceAccount. |
| `serviceAccount.name` | `""` | Override ServiceAccount name. |
| `serviceMonitor.enabled` | `true` | Deploy a Prometheus ServiceMonitor. |
| `serviceMonitor.additionalLabels` | `{}` | Extra labels for the ServiceMonitor. |
| `metrics.enabled` | `true` | Expose a metrics Service. |
| `metrics.port` | `8080` | Metrics port. |
| `portal.enabled` | `false` | Expose the in-operator portal through the gateway. |
| `portal.port` | `4000` | Port the portal listens on inside the operator pod. |
| `portal.hostname` | `""` (apex) | Hostname for the portal's HTTPRoute. Empty falls back to `<operator.baseDomain>`. |
| `operator.targetNamespace` | `"devpod"` | Namespace the operator watches. |
| `operator.baseDomain` | `""` | Base domain for HTTPRoute hostnames. |
| `operator.defaultPort` | `4096` | Default OpenCode port. |
| `operator.gatewayName` | `""` | Gateway resource name for HTTPRoute parentRef. |
| `operator.gatewayNamespace` | `""` | Gateway resource namespace. |
| `operator.workspaceLabel` | `"devpod.sh/workspace-uid"` | Pod label selector. |
| `resources.requests.cpu` | `100m` | CPU request. |
| `resources.requests.memory` | `128Mi` | Memory request. |
| `resources.limits.cpu` | `500m` | CPU limit. |
| `resources.limits.memory` | `256Mi` | Memory limit. |
| `podLabels` | `{}` | Extra pod labels. |
| `podAnnotations` | `{}` | Extra pod annotations. |
| `nodeSelector` | `{}` | Node selector. |
| `tolerations` | `[]` | Tolerations. |
| `affinity` | `{}` | Affinity rules. |
| `namespace` | `""` | Override deployment namespace. |

## Portal

The operator ships with a small in-operator HTTP portal that lists the
OpenCode Endpoints currently reconciled by the operator. The portal is
useful for human navigation — clicking a card opens the corresponding
OpenCode instance in the browser.

**The portal listener is always on inside the operator pod**, regardless
of `portal.enabled`. You can always reach it with:

```bash
kubectl port-forward deploy/<release-name>-devpod-opencode-operator 4000:4000
# then open http://localhost:4000
```

`portal.enabled` controls only whether the chart also creates a
gateway-routable `Service` and `HTTPRoute` for the portal:

- `enabled: false` (default) — listener on inside the pod, but not
  reachable through the gateway. Use `kubectl port-forward` (RBAC-gated).
- `enabled: true` — chart creates a `Service` and `HTTPRoute`. The
  HTTPRoute is exposed through the same gateway as workspace routes,
  so anyone who can reach the gateway can reach the portal.

**Authentication.** The portal has no in-app authentication. Workspace
IDs are not credentials, and the OpenCode Endpoints themselves are
already reachable through the gateway at `<workspace_id>.<baseDomain>`.
If your threat model requires it, apply authentication at the
gateway/proxy layer (e.g. `AuthorizationPolicy`, OAuth2-proxy, mTLS).
When `portal.enabled: true`, treat the portal hostname as semi-public.

## Uninstalling

```bash
helm uninstall devpod-opencode-operator --namespace devpod-system
```

## How It Works

1. The operator lists all Pods in the configured `targetNamespace` that carry the `devpod.sh/workspace-uid` label.
2. For each matching Pod it creates:
   - A **ClusterIP Service** named `<workspace-uid>-opencode` pointing at the OpenCode port.
   - An **HTTPRoute** named `<workspace-uid>-opencode` with hostname `<workspace-uid>.<baseDomain>`, referencing the configured Gateway.
3. Both resources have an `ownerReference` back to the Pod, so Kubernetes garbage-collects them automatically when the Pod is deleted.
4. The operator also runs a small HTTP portal (always on inside the pod;
   optionally exposed through the gateway — see the [Portal](#portal)
   section below).

## See also

- [Main README](../../../README.md) — project overview, installation, and architecture
- [CONTEXT.md](../../../CONTEXT.md) — domain vocabulary (workspace, OpenCode endpoint, etc.)
- [ADR-0005: Portal has no in-app authentication](../../../docs/adr/0005-portal-no-in-app-auth.md) — auth expectations for the portal
