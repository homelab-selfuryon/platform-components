package cnpg

import (
	"list"
	"strconv"
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
)

// CloudNativePG operator. The databases themselves (one `Cluster` per app and environment) come
// with the apps (`database: postgres` in deploy.cue) and live in the team's namespace; their shape
// comes from platform-kit, their images from here.
//
// Images: the operator image and the PostgreSQL images are pinned by digest (registry/latest.json,
// entries `cnpg-operator`, `postgresql` and, during a major upgrade, `postgresql-<old major>`). The operator starts both in tenant namespaces (the
// operator image as the instance pods' bootstrap init container): they are this component's
// `tenantImages`, the only foreign images the tenant image policy allows. Tenant Clusters must take
// PostgreSQL from the ClusterImageCatalog below, never an `imageName` of their own.
#CNPG: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	// ghcr.io/cloudnative-pg/cloudnative-pg; its version must be the chart's appVersion.
	#operatorRef: schema.#Ref & {digest!: _}

	// ghcr.io/cloudnative-pg/postgresql, `<major>.<minor>-<flavour>`, one per major the catalog
	// offers; the first is the newest (the operator's default). A second major is there only while
	// the apps move to the first (platform-kit `#Cluster.postgresMajor`): CNPG upgrades a Cluster in
	// place when its catalog major changes, and needs the old image for that. Such an entry also
	// gets a packageRule in .github/renovate.json that keeps it on its major (`allowedVersions`);
	// both go once every Cluster runs the new major.
	#postgresRefs: [schema.#Ref & {digest!: _}, ...schema.#Ref & {digest!: _}]

	let _operator = "ghcr.io/cloudnative-pg/cloudnative-pg:\(#operatorRef.version)@\(#operatorRef.digest)"
	let _images = [for r in #postgresRefs {
		major: strconv.Atoi(strings.Split(r.version, ".")[0])
		image: "ghcr.io/cloudnative-pg/postgresql:\(r.version)@\(r.digest)"
	}]
	let _postgres = _images[0].image

	// A catalog holds one image per major.
	_uniqueMajors: true & list.UniqueItems([for i in _images {i.major}])

	component: schema.#Component & {
		name:        "cnpg"
		description: "CloudNativePG operator and the PostgreSQL image catalog."
		namespace:   "cnpg-system"
		set:         "platform"

		chart: schema.#Chart & {
			kind:        "helm"
			url:         "https://cloudnative-pg.github.io/charts"
			name:        "cloudnative-pg"
			version:     #ref.version
			releaseName: "cnpg"
		}
		values: {
			crds: create: true
			config: {
				clusterWide: true
				// Default for a Cluster without an image; tenant Clusters use the catalog instead.
				data: POSTGRES_IMAGE_NAME: _postgres
			}
			// The chart writes repository:tag; the tag carries the digest.
			image: {
				repository: "ghcr.io/cloudnative-pg/cloudnative-pg"
				tag:        "\(#operatorRef.version)@\(#operatorRef.digest)"
			}
			monitoring: podMonitorEnabled: false
		}

		manifests: global: clusterImageCatalog: (schema.#PostgresImageCatalog): spec: images: _images

		tenantImages: [_operator, for i in _images {i.image}]

		network: {
			ingress: [
				// Admission webhooks
				schema.Net.apiserverIn & {toPorts: [{ports: [{port: "9443", protocol: "TCP"}]}]},
			]
			egress: [
				schema.Net.apiserverOut,
				// Instance managers: status endpoint (8000) and PostgreSQL (5432) of every cluster.
				{toEntities: ["cluster"], toPorts: [{ports: [{port: "8000", protocol: "TCP"}, {port: "5432", protocol: "TCP"}]}]},
			]
		}

		whitelist: [
			schema.#CRD & {names: ["*.postgresql.cnpg.io"]},
			schema.#ClusterRole & {names: ["cnpg-cloudnative-pg", "cnpg-cloudnative-pg-edit", "cnpg-cloudnative-pg-view"]},
			schema.#ClusterRoleBinding & {names: ["cnpg-cloudnative-pg"]},
			schema.#MutatingWebhook & {names: ["cnpg-mutating-webhook-configuration"]},
			schema.#ValidatingWebhook & {names: ["cnpg-validating-webhook-configuration"]},
			schema.#ClusterImageCatalog & {names: [schema.#PostgresImageCatalog]},
		]
	}
}
