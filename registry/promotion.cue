package registry

import "github.com/homelab-selfuryon/platform-components/schema"

// Promotion policy for `cue cmd promote` (scripts/promote.py has the rules it applies).
//
// holds: components whose pins must not move on any cluster, whatever the source offers. A hold
// lapses after `until`; delete it to lift it earlier. `-t ignore_holds=true` overrides for one run.
// A cluster-wide freeze is `freeze` in the cluster's config (schema.#Cluster).
//
//   holds: "cilium": {reason: "1.21 breaks the host firewall, upstream issue #123", since: "2026-11-23"}
holds: [string]~(N,_): schema.#Hold & {
	// Only components latest.json knows: a typo would hold nothing.
	_known: true & latest[N] != _|_
}
holds: {}
