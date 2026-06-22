# Use the `k8s` library directly, skip Bonny

The controller uses the `k8s` hex package's watch and apply APIs directly, with a plain GenServer running the list-then-watch loop. Bonny is not a dependency.

**Considered options:** Bonny (a higher-level controller framework built on `k8s`). Rejected because Bonny's abstraction is shaped around custom resources with CRD schemas and lifecycle management. This controller watches core Pods and creates two resource types — Bonny adds no value and pulls in an opinionated structure (`operator.ex`, controller modules tied to CRD definitions) that doesn't match the problem. Direct use of `k8s` keeps the dependency surface small, the code straightforward, and the controller logic visible in a single GenServer.
