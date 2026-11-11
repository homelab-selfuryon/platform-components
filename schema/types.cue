package schema

import (
	apps_v1 "cue.dev/x/k8s.io/api/apps/v1"
	core_v1 "cue.dev/x/k8s.io/api/core/v1"
	rbac_v1 "cue.dev/x/k8s.io/api/rbac/v1"
	argo_v1 "cue.dev/x/argo/cd/v1alpha1"
	flux_source_v1 "cue.dev/x/crd/fluxcd.io/source/v1"
	flux_helm_v2 "cue.dev/x/crd/fluxcd.io/helm/v2"
	flux_kustomize_v1 "cue.dev/x/crd/fluxcd.io/kustomize/v1"
	cert_v1 "cue.dev/x/crd/cert-manager.io/v1"
	fluxoperator_v1 "github.com/homelab-selfuryon/platform-components/crd/fluxoperator/v1"
	cilium_v2 "github.com/homelab-selfuryon/platform-components/crd/cilium/v2"
	kyverno_v1 "github.com/homelab-selfuryon/platform-components/crd/kyvernopolicies/v1"
)

// Labels and annotations of the platform.
#Prefix: "homelab-selfuryon.github.io"

// Namespace of Argo CD: Applications live there and preview syncs run as its ServiceAccounts
// (contract: meta/delivery.md, gitops schema/render.cue).
#ArgoCDNamespace: "argocd-system"

// The ClusterImageCatalog of PostgreSQL images (components/storage/cnpg). Tenant Clusters must use it
// (policy tenant-postgres-clusters); platform-kit renders the reference (meta/delivery.md).
#PostgresImageCatalog: "postgresql"

_defaultLabels: {
	"app.kubernetes.io/part-of": "homelab-selfuryon"
	"\(#Prefix)/managed-by":     *"platform" | string
}

// An object of a kind without a CUE schema in this repository: apiVersion and
// kind are fixed by the type that uses it.
#Raw: {
	apiVersion!: string
	kind!:       string
	metadata!: {
		name!:      string
		namespace?: string
		labels?: [string]:      string
		annotations?: [string]: string
		...
	}
	...
}

// Cluster-scoped kinds, keyed by type and then by name.
#GlobalTypes: [string]: [string]~(ID,_): {
	metadata: name:   *ID | string
	metadata: labels: _defaultLabels
}

#GlobalTypes: {
	namespace: [string]:          core_v1.#Namespace
	clusterRole: [string]:        rbac_v1.#ClusterRole
	clusterRoleBinding: [string]: rbac_v1.#ClusterRoleBinding

	// Cert-manager
	clusterIssuer: [string]: cert_v1.#ClusterIssuer

	// Cilium
	ciliumClusterwideNetworkPolicy: [string]: cilium_v2.#CiliumClusterwideNetworkPolicy

	// Kyverno (CEL policies, policies.kyverno.io)
	validatingPolicy: [string]:      kyverno_v1.#ValidatingPolicy
	imageValidatingPolicy: [string]: kyverno_v1.#ImageValidatingPolicy
	generatingPolicy: [string]:      kyverno_v1.#GeneratingPolicy
	deletingPolicy: [string]:        kyverno_v1.#DeletingPolicy

	// Gateway API / Envoy Gateway (no schema here; see components/network)
	gatewayClass: [string]: #Raw & {apiVersion: "gateway.networking.k8s.io/v1", kind: "GatewayClass"}

	// CloudNativePG (no schema here; see components/storage/cnpg)
	clusterImageCatalog: [string]: #Raw & {apiVersion: "postgresql.cnpg.io/v1", kind: "ClusterImageCatalog"}
}

// Namespaced kinds, keyed by namespace, type and name.
#ScopedTypes: [string]: [string]~(ID,_): {
	metadata: name:   *ID | string
	metadata: labels: _defaultLabels
}

#ScopedTypes: {
	serviceAccount: [string]: core_v1.#ServiceAccount
	role: [string]:           rbac_v1.#Role
	roleBinding: [string]:    rbac_v1.#RoleBinding
	configMap: [string]:      core_v1.#ConfigMap
	service: [string]:        core_v1.#Service
	deployment: [string]:     apps_v1.#Deployment
	statefulSet: [string]:    apps_v1.#StatefulSet
	daemonSet: [string]:      apps_v1.#DaemonSet
	resourceQuota: [string]:  core_v1.#ResourceQuota
	limitRange: [string]:     core_v1.#LimitRange

	// Cilium
	ciliumNetworkPolicy: [string]: cilium_v2.#CiliumNetworkPolicy

	// Cert-manager
	certificate: [string]: cert_v1.#Certificate
	issuer: [string]:      cert_v1.#Issuer

	// Flux
	gitRepository: [string]:  flux_source_v1.#GitRepository
	helmRepository: [string]: flux_source_v1.#HelmRepository
	ociRepository: [string]:  flux_source_v1.#OCIRepository
	helmRelease: [string]:    flux_helm_v2.#HelmRelease
	kustomization: [string]:  flux_kustomize_v1.#Kustomization
	fluxInstance: [string]:   fluxoperator_v1.#FluxInstance

	// Argo CD
	appProject: [string]:  argo_v1.#AppProject
	application: [string]: argo_v1.#Application

	// Without schema
	gateway: [string]:             #Raw & {apiVersion: "gateway.networking.k8s.io/v1", kind: "Gateway"}
	envoyProxy: [string]:          #Raw & {apiVersion: "gateway.envoyproxy.io/v1alpha1", kind: "EnvoyProxy"}
	secretProviderClass: [string]: #Raw & {apiVersion: "secrets-store.csi.x-k8s.io/v1", kind: "SecretProviderClass"}
}

// A set of objects: cluster-scoped ones plus the ones of each namespace.
#Manifests: {
	global: #GlobalTypes
	scoped: [string]: #ScopedTypes
	scoped: [string]~(ns,_): [string]~(type,_): [string]~(name,_): {
		metadata: namespace: ns
	}
}
