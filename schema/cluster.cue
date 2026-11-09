package schema

// Cluster-wide facts that components derive their configuration from.
#Cluster: {
	name!: string

	// Release layer: the sets are released in this order (the order is also the order `gitops`
	// applies them in). Every component belongs to one of them.
	sets: [...string]

	// Publish set artifacts on `main`. Off for clusters that exist only as manifests (rendered
	// and diffed in PRs, never deployed).
	publish: *true | bool

	// Version channel, see registry.#Resolve.
	channel: *"fast" | "stable"

	// Base domain of the platform: Gateway hostnames, external-dns records, certificates.
	domain!: string

	kubernetes: {
		// `helm template --kube-version`
		version!: =~"^v?[0-9]+\\.[0-9]+\\.[0-9]+$"
		// `helm template --api-versions` (group/version or group/version/Kind); what Capabilities
		// checks in charts should see besides the built-in APIs.
		apiVersions: [...string]
	}

	network: {
		// Primary family first; pod/service CIDRs must match Talos KubeNetworkConfig.
		podCIDRs!:     [...string]
		serviceCIDRs!: [...string]
		// Host interfaces Cilium attaches to.
		devices!: [...string]
		// Sources allowed to reach the node itself (Talos API, kube-apiserver, DHCP, ICMP)
		// through the Cilium host firewall; everything else from outside the cluster is dropped.
		trustedCIDRs!: [...string]
		// Cilium policyAuditMode: policies only log what they would drop.
		policyAudit: *false | bool
	}

	security: {
		// Image registries platform pods may pull from (prefixes; enforced by Kyverno).
		allowedRegistries: *[
			"docker.io/",
			"ghcr.io/",
			"quay.io/",
			"registry.k8s.io/",
			"reg.kyverno.io/",
			"ecr-public.aws.com/",
		] | [...string]
	}

	storage: {
		// Host path of the Talos user volume backing local-path PVs.
		localPath: *"/var/mnt/local-storage" | string
	}

	// ACME account e-mail for Let's Encrypt. Optional (Let's Encrypt sends no expiry mail any more):
	// unset, the account has no contact.
	acme: email?: string

	// Identity of the workflows that sign and publish artifacts (cosign keyless).
	artifacts: {
		registry: *"ghcr.io/homelab-selfuryon" | string
		issuer:   *"https://token.actions.githubusercontent.com" | string
		// Workflow identities, as regexes for Flux and Kyverno.
		workflows: {
			base: "^https://github\\.com/homelab-selfuryon/github-workflows/\\.github/workflows/"
			// gitops signs its own artifact from its own workflow: the subject pins repository and ref.
			gitopsPublish: "^https://github\\.com/homelab-selfuryon/gitops/\\.github/workflows/publish\\.yaml@refs/heads/main$"
			appRelease:    "\(base)app-release\\.yaml@.+$"
			appPreview:    "\(base)app-preview\\.yaml@.+$"
		}
	}
}
