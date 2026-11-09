{ pkgs, config, ... }:
{
  # Cluster access for bootstrap and break-glass (docs/bootstrap.md): paths only, the files live in
  # the git-ignored .secrets/ and come from the break-glass bundle.
  env = {
    TALOSCONFIG = "${config.devenv.root}/.secrets/talos/alpha-01/talosconfig";
    KUBECONFIG = "${config.devenv.root}/.secrets/kubernetes/config";
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

  enterTest = ''
    bash scripts/cue-vet.bash
  '';
}
