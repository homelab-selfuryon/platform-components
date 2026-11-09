@extern(embed)

package registry

import (
	"strings"
	"github.com/homelab-selfuryon/platform-components/schema"
)

// Newest upstream versions of every component, kept current by Renovate
// (regex manager over latest.json, see renovate.json).
_latest: _ @embed(file="latest.json")

// A version as written in latest.json and pins.json: "1.2.3" or "1.2.3@sha256:<hex>".
#Versions: [string]: string

latest: #Versions & {
	for e in _latest.components {
		(e.name): [
			if e.digest != _|_ {"\(e.version)@\(e.digest)"},
			e.version,
		][0]
	}
}

// Versions a cluster runs, from its channel and pins (clusters/<name>/pins.json):
//   fast:   latest.json, with pins on top (Renovate updates roll out directly)
//   stable: pins only; every component the cluster uses must be pinned
#Resolve: {
	#channel: "fast" | "stable"
	#pins:    #Versions

	versions: #Versions
	if #channel == "fast" {
		versions: {
			for name, v in latest {
				(name): *v | string
			}
		} & #pins
	}
	if #channel == "stable" {
		versions: #pins
	}

	// The same, split into version and digest.
	out: [string]: schema.#Ref
	for name, v in versions {
		let _p = strings.Split(v, "@")
		out: (name): {
			version: _p[0]
			if len(_p) > 1 {
				digest: _p[1]
			}
		}
	}
}
