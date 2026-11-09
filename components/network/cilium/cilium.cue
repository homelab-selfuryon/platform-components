package cilium

import (
	"strings"
	"github.com/homelab-selfuryon/platform-components/schema"
)

// Cilium on Talos: native routing, netkit, eBPF host routing and masquerading, kube-proxy
// replacement through KubePrism, LoadBalancer IPs from node addresses (node IPAM), host
// firewall (see components/network/hostfirewall) and Hubble. IP families follow the cluster's
// pod CIDRs. Installed by `cue cmd bootstrap`, then adopted by Flux (same render).
#Cilium: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	let _v4 = [for c in #cluster.network.podCIDRs if !strings.Contains(c, ":") {c}]
	let _v6 = [for c in #cluster.network.podCIDRs if strings.Contains(c, ":") {c}]

	component: schema.#Component & {
		name:        "cilium"
		description: "CNI: kube-proxy replacement, network policy, host firewall, Hubble."
		namespace:   "kube-system"
		set:         "system"
		// kube-system exists; Cilium shares it with Kubernetes' own pods.
		createNamespace: false
		privileged:      true
		reason:          "CNI: the datapath and the CRDs that every network policy of the platform depends on; must run before Flux can start any pod."
		// Host-network pods; policies for kube-system are not generated.
		network: policy: false
		// The chart also writes to cilium-secrets.
		targetNamespace: false

		chart: schema.#Chart & {
			#ref: _ref
			kind: "helm"
			url:  "https://helm.cilium.io"
			name: "cilium"
		}
		values: {
			ipv4: enabled: len(_v4) > 0
			ipv6: enabled: len(_v6) > 0

			ipam: mode: "kubernetes"
			k8s: {
				requireIPv4PodCIDR: len(_v4) > 0
				requireIPv6PodCIDR: len(_v6) > 0
			}

			routingMode: "native"
			if len(_v4) > 0 {
				ipv4NativeRoutingCIDR: _v4[0]
				enableIPv4Masquerade:  true
			}
			if len(_v6) > 0 {
				ipv6NativeRoutingCIDR: _v6[0]
				enableIPv6Masquerade:  true
			}

			// Pods reach each other on the node without a route to install.
			autoDirectNodeRoutes: false

			kubeProxyReplacement: true
			// KubePrism
			k8sServiceHost: "localhost"
			k8sServicePort: 7445

			devices: #cluster.network.devices

			bpf: {
				datapathMode:      "netkit"
				masquerade:        true
				hostLegacyRouting: false
			}

			// Host firewall: a CiliumClusterwideNetworkPolicy with a nodeSelector filters traffic
			// to the node itself.
			hostFirewall: enabled: true
			policyAuditMode: #cluster.network.policyAudit
			// The agent reads cilium-config only at start.
			rollOutCiliumPods: true

			nodeIPAM: enabled: true
			defaultLBServiceIPAM: "nodeipam"
			loadBalancer: acceleration: "disabled"

			operator: replicas: 1

			// Talos: cgroup v2 is already mounted, SYS_MODULE is not allowed.
			cgroup: {
				autoMount: enabled: false
				hostRoot: "/sys/fs/cgroup"
			}
			securityContext: capabilities: {
				ciliumAgent:      ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
				cleanCiliumState: ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
			}

			// Hubble: flows through the relay (cluster-internal); no UI. Certificates come from the
			// chart's cronjob (the helm method would generate a CA at every render).
			hubble: {
				enabled: true
				relay: enabled: true
				ui: enabled:    false
				tls: auto: method: "cronJob"
			}
			prometheus: enabled: false

			// Gateway API is served by Envoy Gateway.
			gatewayAPI: enabled: false
		}

		whitelist: [
			schema.#CRD & {names: ["*.cilium.io"]},
			schema.#Namespace & {names: ["cilium-secrets"]},
			schema.#ClusterRole & {names: ["cilium", "cilium-operator", "hubble-generate-certs"]},
			schema.#ClusterRoleBinding & {names: ["cilium", "cilium-operator", "hubble-generate-certs"]},
		]
	}
}
