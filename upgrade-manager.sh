#!/bin/sh
systemNodepool=sys
systemNodepoolCurrentVersion=$(kubectl get nodes --selector='nodepool-type=system' -o jsonpath='{.items..metadata.labels.nodepool-kubernetes-version})' | awk 'FNR==1{print $1}')
echo "System nodepool is running Kubernetes version $systemNodepoolCurrentVersion"
exit
liveNodepool=$(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items..metadata.labels.nodepool-type})' | awk 'FNR==1{print $1}')
#
# Get version of live nodepool
#
currentVersion=$(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items..metadata.labels.nodepool-kubernetes-version})' | awk 'FNR==1{print $1}')

clusterName=$(jq .clusterName ./upgrade-manager.json -r)
resourceGroup=$(jq .resourceGroup ./upgrade-manager.json -r)
targetVersion=$(jq .targetVersion ./upgrade-manager.json -r)
action=$(jq .action ./upgrade-manager.json -r)
controlPlaneCurrentVersion=$(az aks show --resource-group $resourceGroup --name $clusterName --query kubernetesVersion -o tsv)

echo "Action is $action"
echo "Target version is $targetVersion"
echo "Cluster is $clusterName in resource group $resourceGroup running Kubernetes version $controlPlaneCurrentVersion"

# Should check if target version is available for the cluster. Need to get cluster region, get versions, search with jq to see if version is in the list of orchestrator versions

if [ "$liveNodepool" == "user-blue" ]; then
    targetNodepool="user-green"
    echo "Blue nodepool is live running Kubernetes version $currentVersion"
else
    targetNodepool="user-blue"
    echo "Green nodepool is live running Kubernetes version $currentVersion"
fi

if [ "$action" == "create" ]; then
    #
    # Cluster control plane needs to be upgraded first
    #
    if [ "$controlPlaneCurrentVersion" != "$targetVersion" ]; then
        echo "Upgrading cluster control plane to $targetVersion"
        az aks upgrade --resource-group $resourceGroup --name $clusterName --control-plane-only --kubernetes-version $targetVersion --yes -o table
    else
        echo "Cluster control plane is already running $targetVersion"
    fi
    #
    # Deploy a new nodepool with the target version
    #
    #
    # Check if nodepool already deployed
    #
    targetNodepoolCount=$(kubectl get nodes --selector='nodepool-state=target' -o json | jq '(.items) | length')
    if [ $targetNodepoolCount -eq 0 ]; then
        echo "Creating nodepool $targetNodepool with Kubernetes version $targetVersion"
        if [ "$targetNodepool" == "user-blue" ]; then
            #
            # Deploy new blue nodepool
            #
            terraform apply -var="blue_active=true" -var="blue_state=target" -var="blue_kubernetes_version=$targetVersion" -var="green_active=true" -var="green_state=live" -var="green_kubernetes_version=$currentVersion" -var="cluster_kubernetes_version=$targetVersion"

        else
            #
            # Deploy new green nodepool
            #
            terraform apply -var="blue_active=true" -var="blue_state=live" -var="blue_kubernetes_version=$currentVersion" -var="green_active=true" -var="green_state=target" -var="green_kubernetes_version=$targetVersion" -var="cluster_kubernetes_version=$targetVersion"
        fi
    else
        echo "Nodepool $targetNodepool already exists"
    fi
fi

if [ "$action" == "migrate" ]; then
    # Get list of nodes and iterate through them
    echo "Adding taints to nodes in nodepool $liveNodepool"
    for node in $(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items[*].metadata.name}'); do
        kubectl taint node $node Upgrading=:NoSchedule
    done

    echo "Draining nodes in nodepool $liveNodepool"
    for node in $(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items[*].metadata.name}'); do
        kubectl drain $node --ignore-daemonsets --delete-local-data --force
    done

fi

if [ "$action" == "delete" ]; then
    echo "Removing nodepool $liveNodepool"
    if [ "$targetNodepool" == "user-blue" ]; then
        #
        # Delete green nodepool
        #
        terraform apply -var="blue_active=true" -var="blue_state=live" -var="blue_kubernetes_version=$targetVersion" -var="green_active=false" -var="cluster_kubernetes_version=$targetVersion"

    else
        #
        # Delete blue nodepool
        #
        terraform apply -var="blue_active=false" -var="green_active=true" -var="green_state=live" -var="green_kubernetes_version=$targetVersion" -var="cluster_kubernetes_version=$targetVersion"
    fi
 fi

 if [ "$action" == "system-upgrade" ]; then
    if [ "$controlPlaneCurrentVersion" != "$targetVersion" ]; then
        echo "Upgrading cluster control plane to $targetVersion"
        az aks upgrade --resource-group $resourceGroup --name $clusterName --control-plane-only --kubernetes-version $targetVersion --yes -o table
    else
        echo "Cluster control plane is already running $targetVersion"
    fi
    echo "Upgrading system nodepool to $targetVersion"
    if [ "$systemNodepoolCurrentVersion" != "$targetVersion" ]; then
        az aks nodepool upgrade --cluster-name $clusterName --name $systemNodepool --resource-group $resourceGroup --kubernetes-version $targetVersion --yes
    else
        echo "System nodepool is already running $targetVersion"
    fi
 fi
