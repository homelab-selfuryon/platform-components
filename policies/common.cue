package policies

import (
	"encoding/json"
	"regexp"
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
	cilium_v2 "github.com/homelab-selfuryon/platform-components/crd/cilium/v2"
)

// Labels the platform sets on tenant namespaces, and the opt-in for exposing Services.
_team:   "\(schema.#Prefix)/team"
_env:    "\(schema.#Prefix)/env"
_expose: "\(schema.#Prefix)/expose"

// A shell glob (`*`) as an anchored RE2 regular expression.
#GlobRegex: {
	#g:  string
	out: "^" + strings.Join([for p in strings.Split(#g, "*") {regexp.QuoteMeta(p)}], ".*") + "$"
}

// Namespaces of the teams.
_tenantNS: matchExpressions: [{key: _team, operator: "Exists"}]

// Pods (CREATE/UPDATE), with every container of the pod in variables.containers.
_pods: {
	evaluation: background: enabled: true
	matchConstraints: resourceRules: [{
		apiGroups:   [""]
		apiVersions: ["v1"]
		operations:  ["CREATE", "UPDATE"]
		resources:   ["pods"]
	}]
	variables: [{
		name:       "containers"
		expression: "object.spec.containers + object.spec.?initContainers.orValue([]) + object.spec.?ephemeralContainers.orValue([])"
	}, ...]
}

// Shared by the image verification policies: pods (and through autogen their controllers) with the
// images of the platform's registry.
_ivp: {
	validationActions: ["Deny"]
	evaluation: background: enabled: false
	matchConstraints: resourceRules: [{
		apiGroups:   [""]
		apiVersions: ["v1"]
		operations:  ["CREATE", "UPDATE"]
		resources:   ["pods"]
	}]
	matchImageReferences: [{glob: "ghcr.io/homelab-selfuryon/*"}]
	...
}

// A GeneratingPolicy that creates #object in every Namespace matching #condition (CEL over the
// Namespace). #object is typed CUE without a namespace (generator.Apply sets it); it reaches CEL as
// JSON through json.unmarshal.
#Generate: {
	#condition!: string
	#object!: {
		apiVersion!: string
		kind!:       string
		metadata!: name!: string
		...
	}

	let _json = json.Marshal(#object)

	// The JSON is embedded in a single-quoted CEL string.
	_quoted: _json & !~"'"

	spec: {
		evaluation: {
			synchronize: enabled:      true
			generateExisting: enabled: true
		}
		matchConstraints: resourceRules: [{
			apiGroups:   [""]
			apiVersions: ["v1"]
			operations:  ["CREATE", "UPDATE"]
			resources:   ["namespaces"]
		}]
		matchConditions: [{name: "namespace", expression: #condition}]
		generate:        [{expression: "generator.Apply(object.metadata.name, [json.unmarshal('\(_quoted)')])"}]
	}
}

// Type-checks a CiliumNetworkPolicy spec against the schema (`spec` is optional in the schema, so
// it can not be selected from the definition directly).
_cnpSpec: {
	#spec: _
	out: (cilium_v2.#CiliumNetworkPolicy & {
		metadata: {name: "typecheck", namespace: "typecheck"}
		spec:     #spec
	}).spec
}
