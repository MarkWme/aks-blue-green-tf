# AKS Upgrades with blue / green nodepools and Terraform

## Introduction

This repo provides an example of how you can upgrade an Azure Kubernetes Service (AKS) cluster using a blue / green nodepool upgrade methodology with Terraform.

**NOTE** This repo is intended to provide one possible way to implement the described scenario. As such, it serves as inspiration for something you might want to implement yourself and should not be considered production grade!

## What is a blue / green nodepool upgrade

AKS features built in mechanisms to automatically upgrade your cluster to a newer Kubernetes version when one is available. Using this fully automated process, AKS will add new nodes to your cluster, move workloads and remove the old nodes.

In scenarios where more control is required over the upgrade process, you can apply the concept of a blue / green nodepool upgrade. In this scenario you manually carry out the following steps.

1. Deploy a new nodepool to your AKS cluster running the target Kubernetes version you want to upgrade to.
2. Use taints or cordon the old nodes to prevent workloads being deployed there.
3. Drain the old nodes, causing the workloads to move to the new nodepool
4. Delete the old nodepool.

Using the above process, it's possible to carefully monitor the migration process, making sure applications have successfully and cleanly removed themselves from the old nodepool and are running as expected on the new nodepool. If there is a problem, the old nodepool still exists and workloads can be moved back. If all is well, the old nodepool can be removed.

## What's in this repo

This repo shows one way this could be achieved using Terraform.

Initially, a new AKS cluster is deployed using Terraform. The cluster has two nodepools. One is a **System** nodepool, which is where Kubernetes system related pods will be running. The second nodepool is a **User** nodepool, which is where your applications will run.

The first User nodepool is designated "blue" and marked, using Kubernetes labels, as being "live".

A script is used to determine what actions to take. If you tell the script that you want to `create` then it will create a new User nodepool. The first time you do this, it will be designated "green" and marked as being the "target".

Once the "green" nodepool is deployed, you can tell the script that you want to `migrate`. This will initiate the process of cordoning and draining the old (blue) nodepool and your workloads will move to the new (green) nodepool.

When you are happy that everything is working as expected, you can tell the script that you want to `delete`. This will cause the script to delete the old (blue) nodepool and designate the new (green) nodepool as "live".

The next time you run this process, the blue and green roles will be reversed. A new blue nodepool will be created, workloads moved to it and then the green nodepool is deleted.

You need not concern yourself with the blue / green parts of this. The script automatically works out which of the blue or green nodepools is currently live and which will become the new target environment. All you need to do is specify the name and resource group of the cluster, the version of Kubernetes you want to migrate to and the action you need the script to perform.

The actions are issued to the script via a JSON configuration file. The idea of this is that you can then update this JSON file and push to a Git repo and have a build process that's triggered by this file being updated. The build process then runs the script, which reads the configuration file and performs the actions.

## How to use

The file `upgrade-manager.json` is configured with the name and resource group of the AKS cluster you want to upgrade, the target Kubernetes version you want to upgrade to and the action you want the script to perform.

```json
{
    "clusterName": "aks-cluster-name",
    "resourceGroup": "aks-cluster-resource-group",
    "targetVersion": "kubernetes version to update to",
    "action": "action type"
}
```

The `upgrade-manager.sh` script recognises the following actions

### system-upgrade

`system-upgrade` will upgrade the [System nodepool](https://learn.microsoft.com/azure/aks/use-system-pools?tabs=azure-cli) to the target Kubernetes version. The upgrade is performed using the standard AKS upgrade mechanism (i.e. running `az aks nodepool upgrade ...`).

When upgrading the System nodepool, the AKS control plane cannot be running an older version of Kubernetes than the version you want to upgrade the nodepools to. Therefore, before the System nodepool is updated, the version of the AKS control plane is checked, and if it's older than the target version, it will be upgraded first.

### create

`create` will deploy a new User nodepool running the target Kubernetes version. As with the `system-upgrade` action, the AKS control plane is checked to make sure it's not running an older version of Kubernetes than the target version and will be upgraded first if it is older.

The new User nodepool will be labelled `nodepool-state: target`

### migrate

`migrate` will iterate through the nodes in the User nodepool labelled `nodepool-state: live` and add a taint to prevent new workloads being scheduled to run there. After that, it iterates through the nodes again, this time issuing a `drain` command to evict workloads from those nodes. The `drain` process will force those workloads to move to the new nodepool.

### delete

`delete` will delete the User nodepool labelled `nodepool-state: live`. Once that's done, the User nodepool labelled `nodepool-state: target` will be relabelled 'nodepool-state: live`

## Walkthrough

### Dependencies

To use this repo, you'll need

- Azure CLI (`az`)
- Kubernetes CLI (`kubectl`)
- Terraform
- jq

### Initial deployment

This script stores Terraform state in Azure Storage. Create an Azure storage account and add the details to the `backend.hcl` file

```hcl
resource_group_name  = "<name of resource group where storage account resides>"
storage_account_name = "<name of storage account>"
container_name       = "<name of a blob container>"
key                  = "<just some value>"
```

You will need to use the `az` Azure CLI to sign in to the Azure subscription where you want to deploy the AKS cluster.

The `variables.tf` file contains the variables used for the initial deployment. To experiment with upgrading clusters, ensure that the three variables that reference the Kubernetes version are all set to the same value and are all set to an older version of Kubernetes that you can upgrade. You can use the `az aks get-versions` command to see which versions of Kubernetes are available for installation.

Run the `tfinit.sh` script to initialise Terraform.

Then, run `terraform apply` to create the initial AKS deployment.

Once the cluster has been created, you can experiment with upgrading.

### Create a nodepool with a new version of Kubernetes

In the `upgrade-manager.json` file, set the appropriate cluster name and resource group name and adjust the `targetVersion` to something newer than the version you initially installed. Ensure that the `action` is set to `create`

Run the `upgrade-manager.sh` script. The script should confirm the current versions of Kubernetes in use on your cluster and the version you are upgrading to.

You should first see that the script upgrades the AKS control plane to the target Kubernetes version. Nodepools cannot run a version of Kubernetes that's higher than the control plane version, so we upgrade that first.

After the control plane has updated, you should see a new nodepool gets deployed. Using a tool like `k9s` is great for this, as it refreshes regularly and you can see the new nodes being built and coming online.

### Migrate the workloads from the old nodepool to the new nodepool

Update the `upgrade-manager.json` file and set the `action` to `migrate`. Then run the `upgrade-manager.sh` script again. You should see each of the nodes in the old nodepool gets tainted, cordoned and then drained. If you're monitoring with a tool such as `k9s` you will see the node status changes to `SchedulingDisabled` and you should see your workloads move from the old nodepool to the new nodepool.

### Delete the old nodepool

Update the `upgrade-manager.json` file by setting the `action` to `delete`. Then run the `upgrade-manager.sh` script again. You should now see that the old nodepool gets deleted. You will also see that the `nodepool-state` label applied to the nodes in the new nodepool get updated from `target` to `live`.

### Upgrade the system nodepool

Update the `upgrade-manager.json` file and set the `action` to `system-upgrade`. Run the `upgrade-manager.sh` script and it should perform an update of the system nodepool. Again, using a tool like `k9s` will show the AKS upgrade process in progress as it cycles through each of the nodes in the system nodepool.
