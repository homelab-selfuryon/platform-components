package teams

// The notes team: notes-api and notes-stats.
Teams: notes: {
	quota: {
		staging: {requestsCPU: "2", requestsMemory: "2Gi", limitsMemory: "4Gi", pods: "20"}
		prod:    {requestsCPU: "4", requestsMemory: "4Gi", limitsMemory: "8Gi", pods: "30"}
		preview: {requestsCPU: "500m", requestsMemory: "512Mi", limitsMemory: "1Gi", pods: "8", persistentVolumeClaims: "2", requestsStorage: "4Gi"}
	}
}
