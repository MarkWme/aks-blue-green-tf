#!/bin/sh

#
# Read configuration file and place into variables
#

clusterName=$(jq .clusterName ./upgrade-manager.json -r)
resourceGroup=$(jq .resourceGroup ./upgrade-manager.json -r)
targetVersion=$(jq .targetVersion ./upgrade-manager.json -r)
action=$(jq .action ./upgrade-manager.json -r)

#
# Determine which nodepool is currently marked as live
#

liveNodepool=$(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items..metadata.labels.nodepool-type})' | awk 'FNR==1{print $1}')

#
# Get version of live nodepool
#

currentVersion=$(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items..metadata.labels.nodepool-kubernetes-version})' | awk 'FNR==1{print $1}')

#
# Get version of control plane
#

controlPlaneCurrentVersion=$(az aks show --resource-group $resourceGroup --name $clusterName --query kubernetesVersion -o tsv)

#
# Get version of system nodepool
#

systemNodepool=sys
systemNodepoolCurrentVersion=$(az aks nodepool show --cluster-name aks-b9b4 --resource-group aks-b9b4 --name sys | jq .currentOrchestratorVersion -r)

#
# Output details about the cluster and the action we're about to take
#

echo "Action is $action"
echo "Target version is $targetVersion"
echo "Cluster is $clusterName in resource group $resourceGroup running Kubernetes version $controlPlaneCurrentVersion"
echo "System nodepool is running Kubernetes version $systemNodepoolCurrentVersion"

#
# Determine the target nodepool (i.e the one that isn't live) and output details about the live nodepool
#

if [ "$liveNodepool" == "user-blue" ]; then
    targetNodepool="user-green"
    echo "Blue nodepool is live running Kubernetes version $currentVersion"
else
    targetNodepool="user-blue"
    echo "Green nodepool is live running Kubernetes version $currentVersion"
fi

#
# Create action - creates a new nodepool
#

if [ "$action" == "create" ]; then

    #
    # Check if cluster control plane needs to be upgraded first
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
    # First check if nodepool already deployed
    #

    targetNodepoolCount=$(kubectl get nodes --selector='nodepool-state=target' -o json | jq '(.items) | length')
    if [ $targetNodepoolCount -eq 0 ]; then
        echo "Creating nodepool $targetNodepool with Kubernetes version $targetVersion"
        if [ "$targetNodepool" == "user-blue" ]; then

            #
            # Deploy new blue nodepool
            #

            terraform apply -var="blue_active=true" -var="blue_state=target" -var="blue_kubernetes_version=$targetVersion" -var="green_active=true" -var="green_state=live" -var="green_kubernetes_version=$currentVersion" -var="cluster_kubernetes_version=$targetVersion" -auto-approve

        else

            #
            # Deploy new green nodepool
            #

            terraform apply -var="blue_active=true" -var="blue_state=live" -var="blue_kubernetes_version=$currentVersion" -var="green_active=true" -var="green_state=target" -var="green_kubernetes_version=$targetVersion" -var="cluster_kubernetes_version=$targetVersion" -auto-approve
        fi
    else
        echo "Nodepool $targetNodepool already exists"
    fi
fi

#
# Migrate action - migrates workloads from live nodepool to target nodepool
#

if [ "$action" == "migrate" ]; then

    #
    # Get list of nodes and iterate through them to add a taint and drain them
    #

    echo "Adding taints to nodes in nodepool $liveNodepool"
    for node in $(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items[*].metadata.name}'); do
        kubectl taint node $node Upgrading=:NoSchedule
    done

    echo "Draining nodes in nodepool $liveNodepool"
    for node in $(kubectl get nodes --selector='nodepool-state=live' -o jsonpath='{.items[*].metadata.name}'); do
        kubectl drain $node --ignore-daemonsets --delete-emptydir-data --force
    done

fi

#
# Delete action - deletes the live nodepool
#

if [ "$action" == "delete" ]; then
    echo "Removing nodepool $liveNodepool"
    if [ "$targetNodepool" == "user-blue" ]; then

        #
        # Delete green nodepool
        #

        terraform apply -var="blue_active=true" -var="blue_state=live" -var="blue_kubernetes_version=$targetVersion" -var="green_active=false" -var="cluster_kubernetes_version=$targetVersion" -auto-approve

    else

        #
        # Delete blue nodepool
        #

        terraform apply -var="blue_active=false" -var="green_active=true" -var="green_state=live" -var="green_kubernetes_version=$targetVersion" -var="cluster_kubernetes_version=$targetVersion" -auto-approve
    fi
 fi

#
# System upgrade action - upgrades the control plane and system nodepool
#

 if [ "$action" == "system-upgrade" ]; then

    #
    # Check if cluster control plane needs to be upgraded first
    #

    if [ "$controlPlaneCurrentVersion" != "$targetVersion" ]; then
        echo "Upgrading cluster control plane to $targetVersion"
        az aks upgrade --resource-group $resourceGroup --name $clusterName --control-plane-only --kubernetes-version $targetVersion --yes -o table
    else
        echo "Cluster control plane is already running $targetVersion"
    fi

    #
    # Check if system nodepool needs to be upgraded
    #
    
    echo "Upgrading system nodepool to $targetVersion"
    if [ "$systemNodepoolCurrentVersion" != "$targetVersion" ]; then
        az aks nodepool upgrade --cluster-name $clusterName --name $systemNodepool --resource-group $resourceGroup --kubernetes-version $targetVersion --yes
    else
        echo "System nodepool is already running $targetVersion"
    fi
 fi
