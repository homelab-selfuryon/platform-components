package clusterissuers

import "github.com/homelab-selfuryon/platform-components/schema"

#namespace: "cert-manager-system"

// Let's Encrypt through DNS-01 on Cloudflare: `letsencrypt` (production) and `letsencrypt-staging`.
//
// The Cloudflare token (kv/data/platform/<cluster>/cert-manager, key `api-token`) is synced into
// the Secret `cloudflare-api-token` by the CSI driver. The sync happens only while a pod mounts the
// volume, so a small `secret-sync` Deployment (pause image) holds it. It is not part of cert-manager
// itself: cert-manager runs before OpenBao and its CSI provider exist (OpenBao gets its certificate
// from the internal CA).
#ClusterIssuers: {
	#cluster: schema.#Cluster

	let _secret = (schema.#OpenBaoSecret & {
		#clusterName: #cluster.name
		#component:   "cert-manager"
		#key:         "api-token"
		#secret:      "cloudflare-api-token"
	}).out

	let _acme = {
		email: #cluster.acme.email
		privateKeySecretRef: name: string
		solvers: [{dns01: cloudflare: apiTokenSecretRef: {name: "cloudflare-api-token", key: "api-token"}}]
	}

	component: schema.#Component & {
		name:        "cluster-issuers"
		description: "Let's Encrypt ClusterIssuers (DNS-01, Cloudflare) and the Cloudflare token sync."
		namespace:   #namespace
		set:         "platform"
		// cert-manager owns the namespace and its network policies.
		createNamespace: false
		network: policy: false
		dependsOn: ["cert-manager", "openbao-csi-provider"]

		manifests: global: clusterIssuer: {
			letsencrypt: spec: acme: _acme & {
				server: "https://acme-v02.api.letsencrypt.org/directory"
				privateKeySecretRef: name: "letsencrypt-account"
			}
			"letsencrypt-staging": spec: acme: _acme & {
				server: "https://acme-staging-v02.api.letsencrypt.org/directory"
				privateKeySecretRef: name: "letsencrypt-staging-account"
			}
		}

		manifests: scoped: (#namespace): {
			secretProviderClass: "cloudflare-api-token": _secret
			serviceAccount: "secret-sync": automountServiceAccountToken: false
			deployment: "secret-sync": spec: {
				replicas: 1
				selector: matchLabels: app: "secret-sync"
				template: {
					metadata: labels: app: "secret-sync"
					spec: {
						serviceAccountName: "secret-sync"
						securityContext: {
							runAsNonRoot: true
							runAsUser:    65532
							seccompProfile: type: "RuntimeDefault"
						}
						containers: [{
							name:  "pause"
							image: "registry.k8s.io/pause:3.10"
							securityContext: {
								allowPrivilegeEscalation: false
								readOnlyRootFilesystem:   true
								capabilities: drop: ["ALL"]
							}
							resources: {
								requests: {cpu: "5m", memory: "8Mi"}
								limits: memory: "16Mi"
							}
							volumeMounts: [{name: "cloudflare-api-token", mountPath: "/mnt/secrets", readOnly: true}]
						}]
						volumes: [{
							name: "cloudflare-api-token"
							csi: {
								driver:   "secrets-store.csi.k8s.io"
								readOnly: true
								volumeAttributes: secretProviderClass: "cloudflare-api-token"
							}
						}]
					}
				}
			}
		}

		whitelist: [
			schema.#ClusterIssuer & {names: ["letsencrypt", "letsencrypt-staging"]},
		]
	}
}
