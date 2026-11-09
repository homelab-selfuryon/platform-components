package defaults

import (
	"list"
	"github.com/homelab-selfuryon/platform-components/schema"
	"github.com/homelab-selfuryon/platform-components/registry"
	"github.com/homelab-selfuryon/platform-components/render"
	app_cilium "github.com/homelab-selfuryon/platform-components/components/network/cilium"
	app_hostfirewall "github.com/homelab-selfuryon/platform-components/components/network/hostfirewall"
	app_fluxoperator "github.com/homelab-selfuryon/platform-components/components/gitops/fluxoperator"
	app_kyverno "github.com/homelab-selfuryon/platform-components/components/security/kyverno"
	app_gatewayapi "github.com/homelab-selfuryon/platform-components/components/network/gatewayapi"
	app_certmanager "github.com/homelab-selfuryon/platform-components/components/security/certmanager"
	app_internalca "github.com/homelab-selfuryon/platform-components/components/security/internalca"
	app_localpath "github.com/homelab-selfuryon/platform-components/components/storage/localpath"
	app_cnpg "github.com/homelab-selfuryon/platform-components/components/storage/cnpg"
	app_metricsserver "github.com/homelab-selfuryon/platform-components/components/observability/metricsserver"
	app_envoygateway "github.com/homelab-selfuryon/platform-components/components/network/envoygateway"
	app_gateways "github.com/homelab-selfuryon/platform-components/components/network/gateways"
	app_externaldns "github.com/homelab-selfuryon/platform-components/components/network/externaldns"
	app_csidriver "github.com/homelab-selfuryon/platform-components/components/security/csidriver"
	app_openbao "github.com/homelab-selfuryon/platform-components/components/security/openbao"
	app_openbaocsi "github.com/homelab-selfuryon/platform-components/components/security/openbaocsi"
	app_clusterissuers "github.com/homelab-selfuryon/platform-components/components/security/clusterissuers"
	app_argocd "github.com/homelab-selfuryon/platform-components/components/gitops/argocd"
	app_rbac "github.com/homelab-selfuryon/platform-components/components/security/rbac"
	"github.com/homelab-selfuryon/platform-components/teams"
	"github.com/homelab-selfuryon/platform-components/policies"
)

// Everything a cluster needs besides its config and pins: version resolution, the components and
// their render. A cluster unifies #Platform with its config and pins, then overrides values:
//
//   cluster: defaults.#Platform & {config: {...}, #pins: _pins}
//   cluster: components: cilium: values: hubble: relay: enabled: false
//
// Components cannot be removed by unification: a cluster that needs a smaller platform defines
// its own list from the same component packages.
#Cluster: {
	config: schema.#Cluster

	// clusters/<name>/pins.json
	#pins: registry.#Versions

	let _pins = #pins
	versions: (registry.#Resolve & {
		#channel: config.channel
		#pins:    _pins
	}).out

	// The same as strings ("1.2.3" or "1.2.3@sha256:...", the form of pins.json).
	resolved: (registry.#Resolve & {
		#channel: config.channel
		#pins:    _pins
	}).versions

	components: schema.#Components

	rendered: render.#Cluster & {
		#cluster:    config
		#components: components
	}
}

#Platform: #Cluster & {
	// Bring the fields into lexical scope for the references below.
	config:   _
	versions: _

	// The policies come right after what they need (Kyverno, Cilium), before any platform component:
	// nothing in `platform` (external-dns waiting for a token, say) can hold them back.
	config: sets: ["rbac", "system", "policy", "platform", "tenants"]

	components: {
		cilium: (app_cilium.#Cilium & {#cluster: config, #ref: versions.cilium}).component
		"flux-operator": (app_fluxoperator.#Flux & {
			#cluster:  config
			#operator: versions["flux-operator"]
			#flux:     versions.flux
		}).component
		kyverno:         (app_kyverno.#Kyverno & {#cluster: config, #ref: versions.kyverno}).component
		"gateway-api":   (app_gatewayapi.#GatewayAPI & {#cluster: config, #ref: versions["gateway-api"]}).component
		"cert-manager":  (app_certmanager.#CertManager & {#cluster: config, #ref: versions["cert-manager"]}).component
		"internal-ca":   (app_internalca.#InternalCA & {#cluster: config}).component
		"host-firewall": (app_hostfirewall.#HostFirewall & {#cluster: config}).component

		"local-path-provisioner":   (app_localpath.#LocalPath & {#cluster: config, #ref: versions["local-path-provisioner"]}).component
		"metrics-server":           (app_metricsserver.#MetricsServer & {#cluster: config, #ref: versions["metrics-server"]}).component
		"envoy-gateway":            (app_envoygateway.#EnvoyGateway & {#cluster: config, #ref: versions["envoy-gateway"]}).component
		"external-dns":             (app_externaldns.#ExternalDNS & {#cluster: config, #ref: versions["external-dns"]}).component
		cnpg:                       (app_cnpg.#CNPG & {#cluster: config, #ref: versions.cnpg}).component
		"secrets-store-csi-driver": (app_csidriver.#CSIDriver & {#cluster: config, #ref: versions["secrets-store-csi-driver"]}).component
		openbao:                    (app_openbao.#OpenBao & {#cluster: config, #ref: versions.openbao}).component
		"openbao-csi-provider":     (app_openbaocsi.#OpenBaoCSI & {#cluster: config, #ref: versions.openbao}).component
		argocd: (app_argocd.#ArgoCD & {
			#cluster:     config
			#ref:         versions.argocd
			#impersonate: list.Concat([["deployer"], [for _, t in teams.Teams {t.previewDeployer}]])
		}).component

		"cluster-issuers": (app_clusterissuers.#ClusterIssuers & {#cluster: config}).component
		gateways:          (app_gateways.#Gateways & {#cluster: config}).component

		// One component per team in teams/.
		for n, t in teams.Teams {
			"team-\(n)": (teams.#Tenants & {#team: t}).component
		}

		// Derived from the others: the policies bind ServiceAccounts to the components, the rbac set
		// creates them.
		"kyverno-policies": (policies.#Policies & {#cluster: config, #components: _base, #teams: teams.Teams}).component
		rbac:               (app_rbac.#RBAC & {#cluster: config, #components: _noRBAC}).component
	}

	// The policies and rbac are built from everything else, rbac also from the policies. They are
	// kept apart from each other (no component value contains itself).
	let _base = {for k, v in components if k != "rbac" && k != "kyverno-policies" {(k): v}}
	let _noRBAC = _base & {"kyverno-policies": components["kyverno-policies"]}
}
