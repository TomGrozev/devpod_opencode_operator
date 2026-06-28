# ADR 0005 — Portal has no in-app authentication; auth is the proxy's job

**Date:** 2026-06-28 · **Status:** Accepted

## Context

The portal lists operator-owned HTTPRoutes, each linking to its OpenCode
Endpoint. With Q8(a) it is reachable by default only via `kubectl port-forward`
into the operator pod — gated by RBAC for forwarding. With Q9's `portal.enabled:
true` it can also be exposed through the gateway at a chart-configured
hostname, making it reachable by anyone who can reach that URL.

## Decision

The operator adds no authentication layer in the Plug. Users who want auth
when gateway-exposed apply it at their proxy / gateway layer (e.g.
AuthorizationPolicy, OAuth2-proxy, mTLS at the gateway).

## Consequences

- When `portal.enabled: false` (default), the only access path is `kubectl
  port-forward` — already gated by Kubernetes RBAC.
- When `portal.enabled: true`, the portal is open by default at its hostname.
  It enumerates workspace IDs and their endpoint hostnames to any requester.
- Workspace IDs are not credentials. The OpenCode Endpoints themselves are
  independently reachable through the gateway (`<id>.<base_domain>`), so the
  portal leaks no secret that the gateway doesn't already expose per-ID —
  but it does provide an operator-canonical list of IDs, which DNS guessing
  does not. Operators exposing the portal should treat the hostname as
  semi-public and apply auth at the proxy if their threat model requires it.
- No new dependency, no new Config field beyond Q13's `PORTAL_PORT`. The
  README should note the auth-BYO expectation for `portal.enabled: true`.
