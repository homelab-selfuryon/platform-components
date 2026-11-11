package policies

import (
	"github.com/homelab-selfuryon/platform-components/schema"
)

_policy: "tenant-postgres-clusters": {
	#ctx: #Context

	global: validatingPolicy: {
		// PostgreSQL in tenant namespaces: images from the platform's catalog only, no superuser.
		"tenant-postgres-clusters": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: {
				namespaceSelector: _tenantNS
				resourceRules: [{
					apiGroups:   ["postgresql.cnpg.io"]
					apiVersions: ["v1"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["clusters"]
				}]
			}
			validations: [{
				expression: "!has(object.spec.imageName) && object.spec.?imageCatalogRef.kind.orValue('') == 'ClusterImageCatalog' && object.spec.?imageCatalogRef.name.orValue('') == '\(schema.#PostgresImageCatalog)'"
				message:    "Tenant PostgreSQL clusters take their image from the ClusterImageCatalog '\(schema.#PostgresImageCatalog)' (spec.imageCatalogRef), not spec.imageName."
			}, {
				expression: "!object.spec.?enableSuperuserAccess.orValue(false)"
				message:    "Tenant PostgreSQL clusters run without superuser access (spec.enableSuperuserAccess)."
			}]
		}
	}
}
