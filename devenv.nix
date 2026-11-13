{ pkgs, config, ... }:
let
  root = config.devenv.root;
in
{
  # CUE, treefmt (nixfmt, prettier, cue fmt), the secret-scanning hooks and the workflow linters come
  # from platform-kit/devenv/cue.nix (imported in devenv.yaml). The base shell is what CI needs to
  # render and check (it is also what CI caches, so keep it small); `ops` adds the cluster tools.
  packages = with pkgs; [
    (python3.withPackages (p: [ p.pyyaml ])) # scripts/*.py
    kubernetes-helm
    kustomize
    kyverno
    kubeconform
    yq-go
  ];

  # Working with clusters: bootstrap, break-glass, Argo CD, releases by hand. `.envrc` enables it
  # (`use devenv --profile ops`); without direnv: `devenv --profile ops shell`.
  profiles.ops.module = {
    # Paths only (docs/bootstrap.md): the files live in the git-ignored .secrets/ and come from the
    # break-glass bundle; they point at the node's fixed ULA address.
    env = {
      TALOSCONFIG = "${root}/.secrets/talos/alpha-01/talosconfig";
      KUBECONFIG = "${root}/.secrets/kubernetes/config";
    };

    packages = with pkgs; [
      cosign
      oras
      gh
      talosctl
      fluxcd
      kubectl
      age
    ];

    # Argo CD has no API server (core mode): the CLI talks to Kubernetes with the admin kubeconfig,
    # in the namespace of clusters/alpha-01/kubeconfig-argocd.yaml (argocd-system).
    scripts.argocd = {
      description = "argocd CLI in core mode against alpha-01 (namespace argocd-system)";
      exec = ''
        KUBECONFIG="${root}/clusters/alpha-01/kubeconfig-argocd.yaml:${root}/.secrets/kubernetes/config" \
          exec ${pkgs.argocd}/bin/argocd --core "$@"
      '';
    };
  };

  treefmt.config.programs.shfmt.enable = true;

  scripts.vet.exec = "bash scripts/cue-vet.bash";

  enterTest = ''
    bash scripts/cue-vet.bash
  '';
}
