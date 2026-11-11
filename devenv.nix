{ pkgs, config, ... }:
let
  root = config.devenv.root;
in
{
  # Cluster access for bootstrap and break-glass (docs/bootstrap.md): paths only, the files live in
  # the git-ignored .secrets/ and come from the break-glass bundle; they point at the node's fixed ULA
  # address. kubectl, flux and talosctl use them as they are.
  env = {
    TALOSCONFIG = "${root}/.secrets/talos/alpha-01/talosconfig";
    KUBECONFIG = "${root}/.secrets/kubernetes/config";
  };

  # CUE, treefmt (nixfmt, prettier, cue fmt), the secret-scanning hooks and the workflow linters come
  # from platform-kit/devenv/cue.nix (imported in devenv.yaml). Only what this repository adds:
  packages = with pkgs; [
    (python3.withPackages (p: [ p.pyyaml ])) # scripts/*.py
    kubernetes-helm
    kustomize
    kyverno
    kubeconform
    cosign
    oras
    yq-go
    gh
    talosctl
    fluxcd
    kubectl
    age
  ];

  treefmt.config.programs.shfmt.enable = true;

  scripts.vet.exec = "bash scripts/cue-vet.bash";

  # Argo CD has no API server (core mode): the CLI talks to Kubernetes with the admin kubeconfig, in
  # the namespace of clusters/alpha-01/kubeconfig-argocd.yaml (argocd-system).
  scripts.argocd = {
    description = "argocd CLI in core mode against alpha-01 (namespace argocd-system)";
    exec = ''
      KUBECONFIG="${root}/clusters/alpha-01/kubeconfig-argocd.yaml:${root}/.secrets/kubernetes/config" \
        exec ${pkgs.argocd}/bin/argocd --core "$@"
    '';
  };

  enterTest = ''
    bash scripts/cue-vet.bash
  '';
}
