@extern(embed)

package alpha01

import "github.com/homelab-selfuryon/platform-components/clusters:defaults"

_pins: _ @embed(file="pins.json")

// Single-node Talos cluster. Talos machine config lives in ./talos (see talos/gen.sh).
// The networks are private (IPv6 ULA, RFC 1918 LAN); the domain is still a placeholder.
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
			devices:      ["enp2s0"]
			// Networks that may reach Talos API and kube-apiserver through the host firewall: the
			// home ULA site prefix and the LAN.
			trustedCIDRs: ["fdc0:ff20:737b::/48", "192.168.1.0/24"]
			// Rollout of the host firewall and default-deny: log, do not drop.
			policyAudit: true
		}
	}
	#pins: _pins
}
