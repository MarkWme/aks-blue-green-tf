#!/bin/sh
#
# Environment variables needed for deployment
#
# Set these to enable debug logging if required
#
# export TF_LOG=
# export TF_LOG_PATH=
#
# Access key for the Azure Storage account where the Terraform
# state will be held. Use the az command specified to retrieve
# the access key. 
#

#export ARM_ACCESS_KEY=$(az storage account keys list -n psaeuwshared --query '[0].value' -o tsv)

#
# If using Azure AD to authenticate against the backend, use this
#
terraform init -backend-config=backend.hcl

#
# Otherwise, just initialise terraform normally
#
# terraform init
