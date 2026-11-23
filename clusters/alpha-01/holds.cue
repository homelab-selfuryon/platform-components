package alpha01

// Promotion holds on alpha-01 only: `cue cmd promote` leaves these components' pins alone
// (registry/holds.cue holds on every cluster; scripts/promote.py has the rules). A hold names a
// component this cluster runs, lapses after `until`, and is lifted by deleting it.
// `-t ignore_holds=true` overrides for one run.
//
//   cluster: config: holds: "victoria-metrics": {reason: "disk migration first", since: "2026-11-24", until: "2026-12-01"}
cluster: config: holds: {}
