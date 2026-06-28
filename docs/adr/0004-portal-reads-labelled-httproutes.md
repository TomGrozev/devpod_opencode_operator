# Portal data source: list operator-owned HTTPRoutes by label

The portal discovers available devpod workspaces by listing HTTPRoutes that carry the label `app.kubernetes.io/managed-by: devpod-opencode-operator`, not by listing Pods and approximating availability. Each listed HTTPRoute also carries `devpod.sh/workspace-uid: <id>` as a label so the portal can read the workspace ID directly off the route without parsing hostnames.

**Considered options:**

- **List operator-owned HTTPRoutes by label (chosen).** The HTTPRoute is the real source of truth for "an OpenCode endpoint is exposed" — if the route exists, the reconciler applied it successfully. Server-side apply is already idempotent by name+namespace, so the label is not needed for apply convergence; its value is discovery (the portal's data source), kubectl observability (`kubectl get httproutes -l app.kubernetes.io/managed-by=devpod-opencode-operator`), and a future orphan-detection prune pass that lists owned resources and compares against current Pods. Combined with owner references (ADR-0001), a stale route implies a still-extant Pod — the route is garbage-collected with the Pod — so "route exists" is a stronger availability guarantee than `status.phase == "Running"` on the Pod.

- **List Pods and filter by `status.phase == "Running"` (rejected).** Approximates availability; a Running pod may not have its route applied yet (reconcile lag), and a non-Running pod may have a valid route until garbage collection catches up. Also couples the portal to Pod-phase reasoning it doesn't need.

- **List Pods + per-workspace `K8s.get` on the HTTPRoute (rejected).** N+1 API calls per page load for marginal correctness; pushes the portal into resource-graph reasoning.

- **Share the watcher's in-memory state with the portal (rejected, see ADR-0003 reasoning).** Couples a control-plane component to a read-plane concern; the watcher would gain `handle_call` paths and a read model that exists only to render a page.

**Consequences:** the operator must write two invariant labels on every HTTPRoute it creates — `app.kubernetes.io/managed-by: devpod-opencode-operator` and `devpod.sh/workspace-uid: <id>` — and the same managed-by label on the Service for symmetry and cluster-searchability. The `K8s` behaviour gains a `list_http_routes(conn, namespace, label_selector)` callback mirroring `list_pods`'s shape; the production impl (`K8s.Production`) and the Mox-backed test seam both implement it. The portal renders workspaces whose route exists; it does not probe OpenCode liveness on the configured port.
