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
| `image.repository` | `ghcr.io/example/devpod-opencode-operator` | Container image. |
| `image.tag` | `""` (appVersion) | Image tag. |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `leaderElection.enabled` | `true` | Enable leader election for HA. |
| `serviceAccount.create` | `true` | Create a ServiceAccount. |
| `serviceAccount.name` | `""` | Override ServiceAccount name. |
| `serviceMonitor.enabled` | `true` | Deploy a Prometheus ServiceMonitor. |
| `serviceMonitor.additionalLabels` | `{}` | Extra labels for the ServiceMonitor. |
| `metrics.enabled` | `true` | Expose a metrics Service. |
| `metrics.port` | `8080` | Metrics port. |
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

## Uninstalling

```bash
helm uninstall devpod-opencode-operator --namespace devpod-system
```

## How It Works

1. The operator lists all Pods in the configured `targetNamespace` that carry the `devpod.sh/workspace-uid` label.
2. For each matching Pod it creates:
   - A **ClusterIP Service** named `<workspace-id>-opencode` pointing at the OpenCode port.
   - An **HTTPRoute** named `<workspace-id>-opencode` with hostname `<workspace-id>.<baseDomain>`, referencing the configured Gateway.
3. Both resources have an `ownerReference` back to the Pod, so Kubernetes garbage-collects them automatically when the Pod is deleted.
