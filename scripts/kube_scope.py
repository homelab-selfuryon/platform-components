"""Which kinds are cluster-scoped. Shared by the render script and the whitelist check."""

# Built-in cluster-scoped kinds (the API groups do not matter for the platform's purposes).
BUILTIN_CLUSTER_KINDS = {
    "Namespace",
    "Node",
    "PersistentVolume",
    "ClusterRole",
    "ClusterRoleBinding",
    "CustomResourceDefinition",
    "APIService",
    "ValidatingWebhookConfiguration",
    "MutatingWebhookConfiguration",
    "ValidatingAdmissionPolicy",
    "ValidatingAdmissionPolicyBinding",
    "MutatingAdmissionPolicy",
    "MutatingAdmissionPolicyBinding",
    "StorageClass",
    "CSIDriver",
    "CSINode",
    "VolumeAttributesClass",
    "PriorityClass",
    "IngressClass",
    "RuntimeClass",
    "ClusterTrustBundle",
    "PodSecurityPolicy",
    "TokenReview",
    "SubjectAccessReview",
    "CertificateSigningRequest",
    "DeviceClass",
    "ResourceSlice",
    "IPAddress",
    "ServiceCIDR",
}


# Cluster-scoped custom kinds whose CRDs are not part of every render (installed by an operator
# at runtime, like Cilium's, or by another component).
KNOWN_CLUSTER_CRD_KINDS = {
    "CiliumClusterwideNetworkPolicy",
    "CiliumClusterwideEnvoyConfig",
    "CiliumNodeConfig",
    "CiliumCIDRGroup",
    "CiliumLoadBalancerIPPool",
    "ClusterIssuer",
    "GatewayClass",
    "ValidatingPolicy",
    "ImageValidatingPolicy",
    "GeneratingPolicy",
    "DeletingPolicy",
    "MutatingPolicy",
    "ClusterPolicy",
    "ClusterCleanupPolicy",
    "ClusterPolicyReport",
}


def crd_scopes(docs):
    """kind -> True when cluster-scoped, for the CRDs among docs."""
    out = {}
    for d in docs:
        if d and d.get("kind") == "CustomResourceDefinition":
            spec = d.get("spec", {})
            out[spec.get("names", {}).get("kind")] = spec.get("scope") == "Cluster"
    return out


def is_cluster_scoped(doc, crds):
    kind = doc.get("kind")
    if kind in BUILTIN_CLUSTER_KINDS:
        return True
    return bool(crds.get(kind, kind in KNOWN_CLUSTER_CRD_KINDS))
