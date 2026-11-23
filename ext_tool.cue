package platform

import (
	"encoding/json"
	"list"
	"strings"
	"tool/cli"
	"tool/exec"
	"tool/file"

	"github.com/homelab-selfuryon/platform-components/registry"
	pkg_bootstrap "github.com/homelab-selfuryon/platform-components/bootstrap"
	"github.com/homelab-selfuryon/platform-components/render"
	all_clusters "github.com/homelab-selfuryon/platform-components/clusters:clusters"
)

cluster: *null | string @tag(cluster)

// cue cmd clusters: the clusters and whether they publish artifacts (read by the reusable workflows).
command: clusters: print: cli.Print & {
	text: json.Marshal([for n, c in all_clusters.Clusters {
		name:    n
		publish: c.config.publish
		sets:    c.config.sets
	}])
}

_usage: "usage: cue cmd <render|check|bootstrap> -t cluster=<name>"

// cue cmd render -t cluster=<c>
//
// out/<c>/<set>/flux/{kustomization.yaml,kustomizations.yaml}
// out/<c>/<set>/components/<name>/{kustomization.yaml,manifests.yaml}
//
// Charts are rendered with `helm template` (scripts/render_component.py); the set directories are
// what is published (.github/workflows/release.yaml). Scratch files live in out/<c>/.work, the approximate
// render of HelmRelease components in out/<c>/.approx.
command: render: {
	if cluster == null {
		usage: cli.Print & {text: _usage}
	}
	if cluster != null {
		let _c = all_clusters.Clusters[cluster]
		let _base = "out/\(cluster)"

		clean: exec.Run & {cmd: list.Concat([["rm", "-rf", "\(_base)/.work", "\(_base)/.approx"], [for s in _c.config.sets {"\(_base)/\(s)"}]])}

		for set, s in _c.rendered.sets {
			"flux-dir-\(set)": file.MkdirAll & {$after: clean, path: "\(_base)/\(set)/flux"}
			"flux-kustomization-\(set)": file.Create & {
				$after:   command.render["flux-dir-\(set)"]
				filename: "\(_base)/\(set)/flux/kustomization.yaml"
				contents: "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - kustomizations.yaml\n"
			}
			"flux-kustomizations-\(set)": file.Create & {
				$after:   command.render["flux-dir-\(set)"]
				filename: "\(_base)/\(set)/flux/kustomizations.yaml"
				contents: [if s.kustomizations != "" {s.kustomizations}, "# no components in this set\n"][0]
			}

			for n in s.names {
				let r = _c.rendered.components[n]
				let _dir = "\(_base)/\(set)/components/\(n)"
				let _work = "\(_base)/.work/\(set)/\(n)"
				let _comp = _c.components[n]

				"mkdir-\(n)":  file.MkdirAll & {$after: clean, path: _dir}
				"mkwork-\(n)": file.MkdirAll & {$after: clean, path: _work}
				"meta-\(n)": file.Create & {
					$after:   command.render["mkwork-\(n)"]
					filename: "\(_work)/meta.json"
					contents: json.Indent(json.Marshal(r.meta), "", "  ")
				}
				"plain-\(n)": file.Create & {
					$after:   command.render["mkwork-\(n)"]
					filename: "\(_work)/plain.yaml"
					contents: r.plain
				}
				"values-\(n)": file.Create & {
					$after:   command.render["mkwork-\(n)"]
					filename: "\(_work)/values.json"
					contents: json.Marshal(_comp.values)
				}
				"patches-\(n)": file.Create & {
					$after:   command.render["mkwork-\(n)"]
					filename: "\(_work)/patches.json"
					contents: json.Marshal(_comp.postRender)
				}
				"kustomization-\(n)": file.Create & {
					$after:   command.render["mkdir-\(n)"]
					filename: "\(_dir)/kustomization.yaml"
					contents: "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - manifests.yaml\n"
				}
				"run-\(n)": exec.Run & {
					$after: [
						command.render["meta-\(n)"],
						command.render["plain-\(n)"],
						command.render["values-\(n)"],
						command.render["patches-\(n)"],
						command.render["mkdir-\(n)"],
					]
					cmd: ["python3", "-I", "scripts/render_component.py", _work, _dir, "\(_base)/.approx/\(set)/\(n).yaml"]
				}
			}
		}
	}
}

// cue cmd bootstrap -t cluster=<c>: out/<c>/bootstrap.yaml, applied by hand once.
//
// Cilium and Flux Operator (the same render as the components in `system`), the flux-system
// namespace, the ServiceAccounts flux-privileged and gitops-root, and the OCIRepository and root
// Kustomization of the `gitops` artifact. No secrets: the OpenBao seal key is created by hand
// (docs/bootstrap.md).
command: bootstrap: {
	if cluster == null {
		usage: cli.Print & {text: _usage}
	}
	if cluster != null {
		let _c = all_clusters.Clusters[cluster]
		let _base = "out/\(cluster)"
		let _objects = strings.Join((render.#Objects & {#m: (pkg_bootstrap.#Bootstrap & {#cluster: _c.config}).out}).out, "---\n")

		clean: exec.Run & {cmd: ["rm", "-rf", "\(_base)/.bootstrap", "\(_base)/.work/.bootstrap", "\(_base)/bootstrap.yaml"]}
		mkdir: file.MkdirAll & {$after: clean, path: "\(_base)/.bootstrap"}
		objects: file.Create & {
			$after:   mkdir
			filename: "\(_base)/.bootstrap/objects.yaml"
			contents: _objects
		}
		for n in ["cilium", "flux-operator"] {
			let r = _c.rendered.components[n]
			let _comp = _c.components[n]
			let _work = "\(_base)/.work/.bootstrap/\(n)"
			"mkwork-\(n)": file.MkdirAll & {$after: clean, path: _work}
			"meta-\(n)": file.Create & {
				$after:   command.bootstrap["mkwork-\(n)"]
				filename: "\(_work)/meta.json"
				contents: json.Marshal(r.meta)
			}
			"plain-\(n)": file.Create & {
				$after:   command.bootstrap["mkwork-\(n)"]
				filename: "\(_work)/plain.yaml"
				contents: r.plain
			}
			"values-\(n)": file.Create & {
				$after:   command.bootstrap["mkwork-\(n)"]
				filename: "\(_work)/values.json"
				contents: json.Marshal(_comp.values)
			}
			"patches-\(n)": file.Create & {
				$after:   command.bootstrap["mkwork-\(n)"]
				filename: "\(_work)/patches.json"
				contents: json.Marshal(_comp.postRender)
			}
			"run-\(n)": exec.Run & {
				$after: [
					mkdir,
					command.bootstrap["meta-\(n)"],
					command.bootstrap["plain-\(n)"],
					command.bootstrap["values-\(n)"],
					command.bootstrap["patches-\(n)"],
				]
				cmd: ["python3", "-I", "scripts/render_component.py", _work, "\(_base)/.bootstrap/\(n)"]
			}
		}
		assemble: exec.Run & {
			$after: [objects, command.bootstrap["run-cilium"], command.bootstrap["run-flux-operator"]]
			cmd:    ["python3", "-I", "scripts/assemble_bootstrap.py", "\(_base)"]
		}
	}
}

// cue cmd check -t cluster=<c>: whitelist check of the render in out/<c> (run `render` first).
command: check: {
	if cluster == null {
		usage: cli.Print & {text: _usage}
	}
	if cluster != null {
		run: exec.Run & {cmd: ["python3", "-I", "scripts/check_whitelist.py", "out/\(cluster)"]}
	}
}

// cue cmd promote -t to=<cluster> [-t from=<latest|cluster>] [-t components=a,b] [-t exclude=a,b]
//                 [-t allow_major=true] [-t ignore_holds=true] [-t body=<file>]
//
// Moves component versions into clusters/<to>/pins.json, from latest.json or from the versions
// another cluster currently resolves, under the promotion policy: holds (registry/promotion.cue on
// every cluster, `holds` in the target's config on that one), no downgrades, a new major only for
// named components with allow_major.
// scripts/promote.py decides and writes; its docstring has the rules. Without `components` it
// considers every component the target resolves; a named one may also be added to the pins (a new
// component on the stable channel). Digests travel with the version ("1.2.3@sha256:...").
// `body` writes the pull request description: what moves and what was skipped, and why.
to:           *null | string     @tag(to)
from:         *"latest" | string @tag(from)
components:   *"" | string       @tag(components)
exclude:      *"" | string       @tag(exclude)
allow_major:  *false | bool      @tag(allow_major,type=bool)
ignore_holds: *false | bool      @tag(ignore_holds,type=bool)
body:         *"" | string       @tag(body)

let _to = to
let _from = from
let _named = [for s in strings.Split(components, ",") if s != "" {s}]
let _excluded = [for s in strings.Split(exclude, ",") if s != "" {s}]
let _allowMajor = allow_major
let _ignoreHolds = ignore_holds

_promote: {
	_source: registry.#Versions
	if _from == "latest" {
		_source: registry.latest
	}
	if _from != "latest" {
		_source: all_clusters.Clusters[_from].resolved
	}
	_target: all_clusters.Clusters[_to]

	// The input of scripts/promote.py.
	input: {
		target:       _to
		source:       _from
		offered:      _source
		pins:         _target.#pins
		resolved:     [for n, _ in _target.resolved {n}]
		named:        _named
		excluded:     _excluded
		allowMajor:   _allowMajor
		ignoreHolds:  _ignoreHolds
		holds:        registry.holds
		clusterHolds: _target.config.holds
	}
}

command: promote: {
	if to == null {
		usage: cli.Print & {text: "usage: cue cmd promote -t to=<cluster> [-t from=<latest|cluster>] [-t components=a,b] [-t exclude=a,b] [-t allow_major=true] [-t ignore_holds=true] [-t body=<file>]"}
	}
	if to != null {
		run: exec.Run & {
			cmd: list.Concat([
				["python3", "-I", "scripts/promote.py", "--pins", "clusters/\(to)/pins.json", "--latest", "registry/latest.json"],
				[if body != "" {"--body"}, if body != "" {body}],
			])
			stdin: json.Marshal(_promote.input)
		}
	}
}
