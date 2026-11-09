# Gateways

One GatewayClass `envoy` (Envoy Gateway), one EnvoyProxy with `mergeGateways: true`, and one Gateway
per environment in `envoy-gateway-system`: `preview`, `staging`, `prod`, each with a listener
`https` (port 443, TLS terminated with a wildcard certificate from Let's Encrypt, DNS-01):

| Gateway   | Hostname             | Routes attach from namespaces labelled     |
| --------- | -------------------- | ------------------------------------------ |
| `prod`    | `*.<domain>`         | `homelab-selfuryon.github.io/env: prod`    |
| `staging` | `*.staging.<domain>` | `homelab-selfuryon.github.io/env: staging` |
| `preview` | `*.preview.<domain>` | `homelab-selfuryon.github.io/env: preview` |

An app writes only an `HTTPRoute` with `parentRefs` to the Gateway of its environment; the
namespace labels are set by `teams/` (staging, prod) and by admission and Argo (preview).

## Network policy: one proxy for all Gateways

With `mergeGateways` the three Gateways share one Envoy deployment. Envoy Gateway then labels its
pods with the GatewayClass (`gateway.envoyproxy.io/owning-gatewayclass: envoy`), **not** with
`gateway.envoyproxy.io/owning-gateway-name: <env>`: a per-Gateway label cannot exist on a pod that
serves three Gateways. The EnvoyProxy therefore adds the label
`homelab-selfuryon.github.io/component: gateway-proxy` to the pods in `envoy-gateway-system`.
Network policies of apps select the proxy by that label (or by
`gateway.envoyproxy.io/owning-gatewayclass: envoy`).

This differs from the table "Cluster-side names" in delivery.md, which names the per-Gateway label;
the table needs the change above (or the decision to drop `mergeGateways`).
