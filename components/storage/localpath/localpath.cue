package localpath

import "github.com/homelab-selfuryon/platform-components/schema"

// Rancher local-path-provisioner on top of the Talos user volume. The chart is not published to a
// Helm repository, so it is taken from the Git tag.
#LocalPath: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	component: schema.#Component & {
		name:        "local-path-provisioner"
		description: "Local PersistentVolumes on the node's user volume."
		namespace:   "local-path-system"
		set:         "platform"
		psa: {
			level:  "privileged"
			reason: "Helper pods mount the node's host path to create and delete volume directories."
		}

		chart: schema.#Chart & {
			kind:    "git"
			url:     "https://github.com/rancher/local-path-provisioner"
			name:    "local-path-provisioner"
			path:    "deploy/chart/local-path-provisioner"
			version: #ref.version
		}
		values: {
			storageClass: {
				create:            true
				name:              "local-path"
				defaultClass:      true
				reclaimPolicy:     "Delete"
				volumeBindingMode: "WaitForFirstConsumer"
			}
			nodePathMap: [{
				node:  "DEFAULT_PATH_FOR_NON_LISTED_NODES"
				paths: [#cluster.storage.localPath]
			}]
		}

		network: {
			ingress: [schema.Net.sameNamespaceIn]
			egress:  [schema.Net.apiserverOut, schema.Net.sameNamespaceOut]
		}

		whitelist: [
			schema.#StorageClass & {names: ["local-path"]},
			schema.#ClusterRole & {names: ["local-path-provisioner"]},
			schema.#ClusterRoleBinding & {names: ["local-path-provisioner"]},
		]
	}
}
