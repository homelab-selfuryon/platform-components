@extern(embed)

package alpha01

import "github.com/homelab-selfuryon/platform-components/clusters:defaults"

_pins: _ @embed(file="pins.json")

// Single-node Talos cluster. Talos machine config lives in ./talos (see talos/gen.sh).
// Addresses and names are placeholders (RFC 5737 / RFC 3849 documentation ranges): replace them
// with the real ones in your fork; nothing here is a real network.
cluster: defaults.#Platform & {
	config: {
		name:    "alpha-01"
		channel: "stable"
		domain:  "homelab.example"
		kubernetes: {
			version: "v1.37.1"
			apiVersions: [
				"cilium.io/v2",
				"gateway.networking.k8s.io/v1",
				"cert-manager.io/v1",
				"policy/v1/PodDisruptionBudget",
			]
		}
		network: {
			// Dual-stack, IPv6 primary; must match talos/patches/node.yaml.
			podCIDRs:     ["fd00:10:244::/56", "10.244.0.0/16"]
			serviceCIDRs: ["fd00:10:96::/112", "10.96.0.0/12"]
			devices:      ["eth0"]
			// Networks that may reach Talos API and kube-apiserver through the host firewall:
			// placeholders (documentation prefixes).
			trustedCIDRs: ["192.0.2.0/24", "2001:db8:1::/48"]
			// Rollout of the host firewall and default-deny: log, do not drop.
			policyAudit: true
		}
	}
	#pins: _pins
}
