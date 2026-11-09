# Secrets of the platform components

Apps read their secrets as files (platform-kit, OpenBao role `<team>-<env>-<app>`). A few
platform components insist on a Kubernetes Secret instead; they get one from the Secrets Store CSI
driver's `secretObjects` sync. Admission allows `secretObjects` in `*-system` namespaces only
(policy `secretobjects-only-in-system`).

OpenBao side, configured in `platform-terraform/openbao`:

| Component                             | OpenBao role                      | Bound to ServiceAccount            | Reads                                                      | Secret created                             |
| ------------------------------------- | --------------------------------- | ---------------------------------- | ---------------------------------------------------------- | ------------------------------------------ |
| `cert-manager` (issuer `letsencrypt`) | `platform-<cluster>-cert-manager` | `cert-manager-system/secret-sync`  | `kv/data/platform/<cluster>/cert-manager`, key `api-token` | `cert-manager-system/cloudflare-api-token` |
| `external-dns`                        | `platform-<cluster>-external-dns` | `external-dns-system/external-dns` | `kv/data/platform/<cluster>/external-dns`, key `api-token` | `external-dns-system/cloudflare-api-token` |

The sync happens only while a pod mounts the CSI volume: in `external-dns` that is the controller
itself, for cert-manager it is the `secret-sync` Deployment in the `cluster-issuers` component
(cert-manager runs before OpenBao exists, so it cannot be the one that holds the volume).

The SecretProviderClasses use `provider: openbao` with `baoAddress:
https://openbao.openbao-system.svc:8200` and validate the server with the internal CA
(`baoCACertPath: /openbao/tls/ca.crt`, mounted into the provider pods from the `openbao-ca`
Secret that cert-manager issues in `openbao-csi-provider-system`).

The Cloudflare token needs the permission "Zone: DNS: Edit" on the platform's zone and nothing else.
One token per component, so each can be revoked alone.

OpenBao's own seal key is the one secret that is not in OpenBao: see [bootstrap.md](bootstrap.md).
