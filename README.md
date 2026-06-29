# DevPod OpenCode Operator

A Kubernetes operator that watches for [DevPod](https://devpod.sh) workspace Pods
and dynamically creates a **Service** + **HTTPRoute** per workspace to expose
the [OpenCode](https://opencode.ai) instance running inside it. The result is a
stable `https://<workspace-uid>.<your-domain>` URL for every running workspace,
routed through your existing Gateway API gateway.

The operator also ships with a small in-operator **portal** — a single HTML page
that lists every running workspace and its OpenCode link, suitable for human
navigation or a homepage.

## How it works

```
devpod Pod (carries devpod.sh/workspace-uid label)
        │
        │  watched by
        ▼
   ┌─────────────┐ apply  ┌──────────────────┐
   │  Operator   │───────▶│  Service         │──┐
   │  (Elixir)   │        │  <uid>-opencode  │  │ ownerReference
   │             │        └──────────────────┘  │ back to Pod
   │             │ apply  ┌──────────────────┐  │ → garbage-collected
   │             │───────▶│  HTTPRoute       │──┘ when Pod is deleted
   └─────────────┘        │  <uid>.<base>    │
        │                 └──────────────────┘
        │                          │
        ▼                          ▼
   Portal (Plug)        Your Gateway → https://<uid>.<baseDomain>
```

For every devpod Pod that carries the `devpod.sh/workspace-uid` label, the
operator creates:

- A `Service` named `<workspace-uid>-opencode` (ClusterIP), selecting Pods by
  the workspace-uid label, with `targetPort` set to the OpenCode port.
- An `HTTPRoute` named `<workspace-uid>-opencode` with hostname
  `<workspace-uid>.<baseDomain>`, referencing your Gateway.

Both resources carry an `ownerReference` back to the source Pod, so Kubernetes
garbage-collects them when the Pod is deleted. There is no explicit delete
handler — see [ADR-0001](docs/adr/0001-owner-references-for-cleanup.md).

## Prerequisites

- **Kubernetes** 1.24+ (uses [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs)
- **Helm** 3.10+ (for the chart)
- The **Gateway API CRDs** installed in your cluster:

  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
  ```

- An existing **Gateway** resource the operator can reference as the route's `parentRef`.

## Installation

The chart is published as an OCI artifact. Install it with:

```bash
helm install devpod-opencode-operator \
  oci://ghcr.io/tomgrozev/devpod_opencode_operator/devpod-opencode-operator \
  --version 0.2.1 \
  --namespace devpod-system \
  --create-namespace \
  --set operator.baseDomain=workspaces.example.com \
  --set operator.gatewayName=main-gateway \
  --set operator.gatewayNamespace=gateway-system
```

Or from a local checkout:

```bash
helm install devpod-opencode-operator \
  ./deploy/charts/devpod-opencode-operator \
  --namespace devpod-system \
  --create-namespace \
  --set operator.baseDomain=workspaces.example.com \
  --set operator.gatewayName=main-gateway \
  --set operator.gatewayNamespace=gateway-system
```

The chart creates a single-replica Deployment plus a ServiceAccount with
cluster-scoped permissions to read Pods, create Services, and create
HTTPRoutes. See the
[chart README](deploy/charts/devpod-opencode-operator/README.md) for the full
values table.

## Configuration

The operator is configured through environment variables (sourced from a
ConfigMap in the chart) plus a few chart toggles. The three **required** values
are the ones the operator cannot infer:

| Env var             | Helm value                  | Description                                                               |
| ------------------- | --------------------------- | ------------------------------------------------------------------------- |
| `BASE_DOMAIN`       | `operator.baseDomain`       | Base domain used in HTTPRoute hostnames (`<workspace-uid>.<baseDomain>`). |
| `GATEWAY_NAME`      | `operator.gatewayName`      | Name of the Gateway resource the HTTPRoutes attach to.                    |
| `GATEWAY_NAMESPACE` | `operator.gatewayNamespace` | Namespace of that Gateway.                                                |

Optional:

| Env var            | Helm value                 | Default                        | Description                                                                                   |
| ------------------ | -------------------------- | ------------------------------ | --------------------------------------------------------------------------------------------- |
| `TARGET_NAMESPACE` | `operator.targetNamespace` | `devpod`                       | Namespace the operator watches for devpod Pods.                                               |
| `DEFAULT_PORT`     | `operator.defaultPort`     | `4096`                         | OpenCode port if a Pod has no per-instance override.                                          |
| `PORTAL_PORT`      | `portal.port`              | `4000`                         | Port the portal listener binds to inside the pod.                                             |
| —                  | `portal.enabled`           | `false`                        | Create a Service + HTTPRoute to expose the portal through the gateway.                        |
| —                  | `portal.hostname`          | `<operator.baseDomain>` (apex) | Hostname for the portal's HTTPRoute.                                                          |
| `KUBECONFIG`       | —                          | (unset)                        | When unset, the operator uses the in-cluster service account. Set only for local development. |

## Pod contract

The operator reads the following from each Pod:

| Field                                                   | Required | Source          | Purpose                                                                                                                                      |
| ------------------------------------------------------- | -------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `devpod.sh/workspace-uid` (label)                       | yes      | Pod metadata    | The devpod workspace UID. Used as the K8s resource name suffix and in the HTTPRoute hostname.                                                |
| `DEVPOD_WORKSPACE_ID` (env var on the devpod container) | no       | container env   | Friendly display name. Falls back to the UID if unset. Surfaced on the portal and on the `devpod.sh/workspace` label of generated resources. |
| `devpod.sh/opencode-port` (annotation)                  | no       | Pod annotations | Per-Pod OpenCode port. Falls back to `DEFAULT_PORT`.                                                                                         |

The `devpod.sh/workspace-uid` label and the `DEVPOD_WORKSPACE_ID` env var are
both set by DevPod itself on the workspace Pod — you should not need to set
them. The `devpod.sh/opencode-port` annotation is the one knob the operator
exposes for per-instance port overrides.

## The portal

The operator runs a small Bandit-served HTML page that lists every
operator-reconciled HTTPRoute. Each card is a link to its OpenCode instance.

**The portal listener is always on inside the pod.** You can always reach it
with `kubectl port-forward`:

```bash
kubectl port-forward deploy/devpod-opencode-operator 4000:4000
# open http://localhost:4000
```

Gated by Kubernetes RBAC, this is the default access path.

**Optionally**, set `portal.enabled: true` to also expose the portal through
your gateway. When enabled, the chart creates a Service and HTTPRoute for the
portal at `portal.hostname` (defaulting to the apex `<operator.baseDomain>`).
See [ADR-0005](docs/adr/0005-portal-no-in-app-auth.md): the portal has **no
in-app authentication** — the OpenCode endpoints themselves are already
reachable through the gateway at per-workspace hostnames, so the portal adds
no new secret surface. If your threat model requires it, apply auth at the
gateway/proxy layer (e.g. `AuthorizationPolicy`, OAuth2-proxy, mTLS).

## Development

Requires Elixir 1.19 and OTP 28.

```bash
# install deps
mix deps.get

# run tests
mix test

# format
mix format
```

Tests use [Mox](https://hex.pm/packages/mox) against a mock implementation of
`DevpodOpencodeOperator.K8s`, so they run without a live cluster. The mock is
defined in `test/test_helper.exs` and wired in `config/test.exs`.

For local runs against a real cluster, point `KUBECONFIG` at the cluster and
start an `iex` session:

```bash
KUBECONFIG=$HOME/.kube/config \
  BASE_DOMAIN=workspaces.example.com \
  GATEWAY_NAME=main-gateway \
  GATEWAY_NAMESPACE=gateway-system \
  TARGET_NAMESPACE=devpod \
  iex -S mix
```

## Container image

CI builds and publishes the image to GitHub Container Registry on tag pushes
(see [`.github/workflows/publish-image.yml`](.github/workflows/publish-image.yml)):

```
ghcr.io/tomgrozev/devpod_opencode_operator:0.2.0
ghcr.io/tomgrozev/devpod_opencode_operator:latest
```

A multi-stage `Dockerfile` produces a non-root release image based on
`hexpm/elixir:1.19.5-erlang-28.5.0.2-debian-bookworm` → `debian:bookworm-slim`.

## Releasing

The container image and the Helm chart are released independently. They share
the same `origin/master` commit, but are triggered by different tag prefixes
so that a chart-only change doesn't force an app release (and vice versa).

| Tag prefix                       | What it publishes                                                                              | Version source                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------- |
| `v*` (e.g. `v0.2.0`)             | Container image (`ghcr.io/tomgrozev/devpod_opencode_operator:0.2.0`)                           | Git tag name, with leading `v` stripped |
| `chart-v*` (e.g. `chart-v0.2.1`) | Helm chart (`oci://ghcr.io/tomgrozev/devpod_opencode_operator/devpod-opencode-operator:0.2.1`) | `Chart.yaml` `version` field            |

Both workflows require the tag's commit to be reachable from `origin/master`.

Examples:

```bash
# App release only
git tag v0.2.0
git push origin v0.2.0

# Chart release only — no app change required
git tag chart-v0.2.1
git push origin chart-v0.2.1

# Both at once (push two tags in one command)
git tag v0.2.0 chart-v0.2.1
git push origin v0.2.0 chart-v0.2.1
```

For a new app release, update `mix.exs` `version`. For a new chart release,
update `deploy/charts/devpod-opencode-operator/Chart.yaml` `version` (and
`appVersion` if the app itself is being released). The chart version follows
[SemVer](https://semver.org/).

## Documentation

- [`CONTEXT.md`](CONTEXT.md) — domain vocabulary (workspace, OpenCode endpoint, etc.)
- [`docs/adr/`](docs/adr/) — architectural decision records
- [`docs/README.md`](docs/README.md) — documentation index
- [`deploy/charts/devpod-opencode-operator/README.md`](deploy/charts/devpod-opencode-operator/README.md) — Helm chart values reference

## Maintainer

Tom Grozev — [@TomGrozev](https://github.com/TomGrozev)
