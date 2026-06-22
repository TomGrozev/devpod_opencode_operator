# Use owner references for Service and HTTPRoute cleanup

The controller sets the watched Pod as the owner of the generated Service and HTTPRoute, and relies on Kubernetes garbage collection to delete them when the Pod is gone. There is no `delete/1` handler in the reconciler.

**Considered options:** explicit `delete/1` handler that watches for Pod deletion and deletes the Service + HTTPRoute by name. Rejected because it is less reliable (missed delete events during controller downtime leave orphaned resources) and requires the controller to track deterministic names for cleanup. Owner references are the idiomatic Kubernetes pattern, survive controller restarts, and eliminate a class of bugs around missed events. The loss of explicit `DELETE` audit logs is acceptable; the reconcile loop still produces `CREATE`/`UPDATE` log lines.

**Consequences:** the Service and HTTPRoute manifest builders must always include an `ownerReferences` block pointing to the Pod. Any `kubectl` operations that remove the owner reference will cause the generated resources to become orphaned and persist after the Pod is gone.
