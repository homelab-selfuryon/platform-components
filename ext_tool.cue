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

// cue cmd promote -t to=<cluster> [-t from=<latest|cluster>] [-t components=a,b]
//
// Copies component versions into clusters/<to>/pins.json, from latest.json or from the versions
// another cluster currently resolves. Without `components` it touches every component the target
// resolves; an explicit list may also add pins the target does not have yet (a new component on
// the stable channel). Digests travel with the version ("1.2.3@sha256:...").
to:         *null | string     @tag(to)
from:       *"latest" | string @tag(from)
components: *"" | string       @tag(components)

_promote: {
	_source: registry.#Versions
	if from == "latest" {
		_source: registry.latest
	}
	if from != "latest" {
		_source: all_clusters.Clusters[from].resolved
	}

	_target:  all_clusters.Clusters[to]
	_current: _target.#pins
	_only:    [for s in strings.Split(components, ",") if s != "" {s}]
	_names: [
		if len(_only) > 0 for n in _only {n},
		if len(_only) == 0 for n, _ in _target.resolved {n},
	]

	updates: {
		for n in _names if _source[n] != _|_ {
			if _current[n] == _|_ {(n): _source[n]}
			if _current[n] != _|_ if _current[n] != _source[n] {(n): _source[n]}
		}
	}
	// Ordered (name, version) pairs: existing pins keep their place, new ones are appended.
	// Rendered by hand because struct field order is not stable.
	_pairs: list.Concat([[
		for n, v in _current {
			if updates[n] != _|_ {[n, updates[n]]}
			if updates[n] == _|_ {[n, v]}
		},
	], [
		for n, v in updates if _current[n] == _|_ {[n, v]},
	]])
	contents: "{\n" + strings.Join([for p in _pairs {"  \"\(p[0])\": \"\(p[1])\""}], ",\n") + "\n}\n"
	summary: strings.Join([
		for n, v in updates {
			if _current[n] != _|_ {"\(n): \(_current[n]) -> \(v)"}
			if _current[n] == _|_ {"\(n): (unpinned) -> \(v)"}
		},
	], "\n")
}

command: promote: {
	if to == null {
		usage: cli.Print & {text: "usage: cue cmd promote -t to=<cluster> [-t from=<latest|cluster>] [-t components=a,b]"}
	}
	if to != null {
		write: file.Create & {
			filename: "clusters/\(to)/pins.json"
			contents: _promote.contents
		}
		report: cli.Print & {
			$after: write
			text: [
				if len(_promote.updates) == 0 {"\(to): nothing to promote from \(from)"},
				"\(to) <- \(from):\n\(_promote.summary)",
			][0]
		}
	}
}
