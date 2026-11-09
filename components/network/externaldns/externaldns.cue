package externaldns

import "github.com/homelab-selfuryon/platform-components/schema"

#namespace: "external-dns-system"

// external-dns: DNS records in Cloudflare for the Gateways' HTTPRoutes. The API token is a
// Kubernetes Secret synced by the Secrets Store CSI driver from OpenBao
// (kv/data/platform/<cluster>/external-dns, key `api-token`) when the pod starts: a listed exception.
#ExternalDNS: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	let _secret = (schema.#OpenBaoSecret & {
		#clusterName: #cluster.name
		#component:   "external-dns"
		#key:         "api-token"
		#secret:      "cloudflare-api-token"
	}).out

	component: schema.#Component & {
		name:        "external-dns"
		description: "external-dns (Cloudflare) for HTTPRoutes."
		namespace:   #namespace
		set:         "platform"
		dependsOn:   ["secrets-store-csi-driver", "openbao-csi-provider", "gateway-api"]

		chart: schema.#Chart & {
			kind:    "helm"
			url:     "https://kubernetes-sigs.github.io/external-dns/"
			name:    "external-dns"
			version: #ref.version
		}
		values: {
			provider: name: "cloudflare"
			sources:       ["gateway-httproute"]
			domainFilters: [#cluster.domain]
			policy:        "sync"
			registry:      "txt"
			txtOwnerId:    #cluster.name
			env: [{
				name: "CF_API_TOKEN"
				valueFrom: secretKeyRef: {name: "cloudflare-api-token", key: "api-token"}
			}]
			// The mounting pod triggers the Secret sync.
			extraVolumes: [{
				name: "cloudflare-api-token"
				csi: {
					driver:   "secrets-store.csi.k8s.io"
					readOnly: true
					volumeAttributes: secretProviderClass: "cloudflare-api-token"
				}
			}]
			extraVolumeMounts: [{name: "cloudflare-api-token", mountPath: "/mnt/secrets", readOnly: true}]
		}

		manifests: scoped: (#namespace): secretProviderClass: "cloudflare-api-token": _secret

		network: {
			ingress: [schema.Net.sameNamespaceIn]
			egress: [
				schema.Net.apiserverOut,
				// Cloudflare API
				schema.Net.world & schema.Net.https,
			]
		}

		whitelist: [
			schema.#ClusterRole & {names: ["external-dns"]},
			schema.#ClusterRoleBinding & {names: ["external-dns-viewer"]},
		]
	}
}
