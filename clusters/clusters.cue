package clusters

import (
	"github.com/homelab-selfuryon/platform-components/schema"
	"github.com/homelab-selfuryon/platform-components/registry"
	"github.com/homelab-selfuryon/platform-components/render"
	alpha01 "github.com/homelab-selfuryon/platform-components/clusters/alpha-01:alpha01"
)

#Entry: {
	config: schema.#Cluster
	versions: [string]: schema.#Ref
	resolved:   registry.#Versions
	components: schema.#Components
	rendered:   render.#Cluster
	#pins:      registry.#Versions
	...
}

Clusters: [string]: #Entry

Clusters: "alpha-01": alpha01.cluster
