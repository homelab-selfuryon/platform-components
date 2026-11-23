package registry

import "github.com/homelab-selfuryon/platform-components/schema"

// Promotion holds on EVERY cluster: `cue cmd promote` leaves these components' pins alone,
// whatever the source offers (scripts/promote.py has the rules). Holds on one cluster only live in
// clusters/<c>/holds.cue, same shape. A hold lapses after `until`; delete it to lift it earlier.
// `-t ignore_holds=true` overrides for one run.
//
//   holds: "cilium": {reason: "1.21 breaks the host firewall, upstream issue #123", since: "2026-11-23"}
holds: [string]~(N,_): schema.#Hold & {
	// Only components latest.json knows: a typo would hold nothing.
	_known: true & latest[N] != _|_
}
holds: {}
