package bootstrap

import (
	"regexp"

	"github.com/homelab-selfuryon/platform-components/schema"
)

// What `cue cmd bootstrap` applies by hand, once, next to Cilium and Flux Operator (their render is
// the same as the components' in the `system` set, so Flux adopts them):
//
//   flux-system        Namespace
//   flux-privileged    ServiceAccount bound to cluster-admin: the core components' Kustomizations
//   gitops-root        ServiceAccount that may create OCIRepository and Kustomization in flux-system
//                      and nothing else: what the `gitops` artifact can ask Flux to do
//   gitops             OCIRepository (signed artifact, cosign-verified) and the root Kustomization
//                      on its `flux/` directory
//
// The FluxInstance is part of the flux-operator component, not of this list.
#Bootstrap: {
	#cluster: schema.#Cluster

	let _artifact = "\(#cluster.artifacts.registry)/gitops/\(#cluster.name)"

	out: schema.#Manifests & {
		global: {
			namespace: "flux-system": metadata: labels: {
				"pod-security.kubernetes.io/enforce": "restricted"
				"pod-security.kubernetes.io/audit":   "restricted"
				"pod-security.kubernetes.io/warn":    "restricted"
			}
			clusterRoleBinding: "flux-privileged": {
				roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "cluster-admin"}
				subjects: [{kind: "ServiceAccount", name: "flux-privileged", namespace: "flux-system"}]
			}
		}
		scoped: "flux-system": {
			serviceAccount: "flux-privileged": automountServiceAccountToken: false
			serviceAccount: "gitops-root": automountServiceAccountToken:     false

			role: "gitops-root": rules: [{
				apiGroups: ["source.toolkit.fluxcd.io"]
				resources: ["ocirepositories"]
				verbs:     ["get", "list", "watch", "create", "update", "patch", "delete"]
			}, {
				apiGroups: ["kustomize.toolkit.fluxcd.io"]
				resources: ["kustomizations"]
				verbs:     ["get", "list", "watch", "create", "update", "patch", "delete"]
			}]
			roleBinding: "gitops-root": {
				roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "gitops-root"}
				subjects: [{kind: "ServiceAccount", name: "gitops-root", namespace: "flux-system"}]
			}

			ociRepository: gitops: spec: {
				interval: "5m"
				url:      "oci://\(_artifact)"
				ref: tag: "main"
				layerSelector: {
					mediaType: "application/vnd.oci.image.layer.v1.tar+gzip"
					operation: "extract"
				}
				// The artifact is signed by .github/workflows/publish.yaml of the gitops repository on
				// main: the certificate subject pins repository, workflow and ref, so nothing else
				// (another repository, another branch, a reusable workflow) is accepted.
				verify: {
					provider: "cosign"
					matchOIDCIdentity: [{
						issuer:  "^\(regexp.QuoteMeta(#cluster.artifacts.issuer))$"
						subject: #cluster.artifacts.workflows.gitopsPublish
					}]
				}
			}

			kustomization: gitops: spec: {
				interval:      "5m"
				retryInterval: "2m"
				timeout:       "10m"
				path:          "./flux"
				prune:         true
				// Applies the set Kustomizations and returns: each set has its own health checks and
				// dependsOn. Waiting here would hold every new revision of gitops (a fix, a rollback)
				// behind the slowest unready set until the timeout.
				wait:               false
				serviceAccountName: "gitops-root"
				sourceRef:          {kind: "OCIRepository", name: "gitops"}
			}
		}
	}
}
