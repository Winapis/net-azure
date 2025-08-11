#!/bin/bash

# This script creates the following resources in the specified subscription:
# - Custom Azure RBAC role for GitHub Actions service with required network permissions
# - Role assignments for GitHub Actions service principals
# - Resource group
# - Network Security Group rules
# - Virtual network (vnet) and subnet
# - Network Settings with specified subnet and GitHub Enterprise database ID
#
# It also registers the `GitHub.Network` resource provider with the subscription,
# delegates the created subnet to the Actions service via the `GitHub.Network/NetworkSettings`
# resource type, and applies the NSG rules to the created subnet.

# stop on failure
set -e

#set environment
export AZURE_LOCATION=YOUR_AZURE_LOCATION
export SUBSCRIPTION_ID=YOUR_SUBSCRIPTION_ID
export RESOURCE_GROUP_NAME=YOUR_RESOURCE_GROUP_NAME
export VNET_NAME=YOUR_VNET_NAME
export SUBNET_NAME=YOUR_SUBNET_NAME
export NSG_NAME=YOUR_NSG_NAME
export NETWORK_SETTINGS_RESOURCE_NAME=YOUR_NETWORK_SETTINGS_RESOURCE_NAME
export DATABASE_ID=YOUR_DATABASE_ID
export API_VERSION=2024-04-02

# GitHub Actions service principal IDs
export GITHUB_CPS_NETWORK_SERVICE_ID=85c49807-809d-4249-86e7-192762525474
export GITHUB_ACTIONS_API_ID=4435c199-c3da-46b9-a61d-76de3f2c9f82
export CUSTOM_ROLE_NAME=GitHubActionsNetworkRole

# These are the default values. You can adjust your address and subnet prefixes.
export ADDRESS_PREFIX=10.0.0.0/16
export SUBNET_PREFIX=10.0.0.0/24

# Function to create custom role definition
create_custom_role_definition() {
    echo "Creating custom role definition JSON file..."
    cat > /tmp/github-actions-network-role.json << 'EOF'
{
    "Name": "GitHubActionsNetworkRole",
    "Description": "Custom role for GitHub Actions service to manage Azure hosted networks",
    "Actions": [
        "GitHub.Network/operations/read",
        "GitHub.Network/networkSettings/read",
        "GitHub.Network/networkSettings/write",
        "GitHub.Network/networkSettings/delete",
        "GitHub.Network/RegisteredSubscriptions/read",
        "Microsoft.Network/locations/operations/read",
        "Microsoft.Network/locations/operationResults/read",
        "Microsoft.Network/locations/usages/read",
        "Microsoft.Network/networkInterfaces/read",
        "Microsoft.Network/networkInterfaces/write",
        "Microsoft.Network/networkInterfaces/delete",
        "Microsoft.Network/networkInterfaces/join/action",
        "Microsoft.Network/networkSecurityGroups/join/action",
        "Microsoft.Network/networkSecurityGroups/read",
        "Microsoft.Network/publicIpAddresses/read",
        "Microsoft.Network/publicIpAddresses/write",
        "Microsoft.Network/publicIPAddresses/join/action",
        "Microsoft.Network/routeTables/join/action",
        "Microsoft.Network/virtualNetworks/read",
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/read",
        "Microsoft.Network/virtualNetworks/subnets/write",
        "Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/delete",
        "Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/read",
        "Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/write",
        "Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/details/read",
        "Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/validate/action",
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/subscriptions/resourcegroups/deployments/read",
        "Microsoft.Resources/subscriptions/resourcegroups/deployments/write",
        "Microsoft.Resources/subscriptions/resourcegroups/deployments/operations/read",
        "Microsoft.Resources/deployments/read",
        "Microsoft.Resources/deployments/write",
        "Microsoft.Resources/deployments/operationStatuses/read"
    ],
    "NotActions": [],
    "DataActions": [],
    "NotDataActions": [],
    "AssignableScopes": [
        "/subscriptions/SUBSCRIPTION_ID_PLACEHOLDER"
    ]
}
EOF
    
    # Replace subscription ID placeholder
    sed -i "s/SUBSCRIPTION_ID_PLACEHOLDER/$SUBSCRIPTION_ID/g" /tmp/github-actions-network-role.json
    echo "Custom role definition created at /tmp/github-actions-network-role.json"
}

echo
echo login to Azure
. az login --output none

echo
echo set account context $SUBSCRIPTION_ID
. az account set --subscription $SUBSCRIPTION_ID

echo
echo Register resource provider GitHub.Network
. az provider register --namespace GitHub.Network

echo
echo Creating custom role definition for GitHub Actions service
create_custom_role_definition

echo
echo Creating custom role $CUSTOM_ROLE_NAME
if . az role definition list --name "$CUSTOM_ROLE_NAME" --subscription "$SUBSCRIPTION_ID" --query "[0].id" --output tsv | grep -q "."; then
    echo "Custom role $CUSTOM_ROLE_NAME already exists, updating..."
    . az role definition update --role-definition /tmp/github-actions-network-role.json
else
    echo "Creating new custom role $CUSTOM_ROLE_NAME..."
    . az role definition create --role-definition /tmp/github-actions-network-role.json
fi

echo
echo Assigning custom role to GitHub CPS Network Service
. az role assignment create --assignee "$GITHUB_CPS_NETWORK_SERVICE_ID" --role "$CUSTOM_ROLE_NAME" --scope "/subscriptions/$SUBSCRIPTION_ID" || echo "Warning: Role assignment for GitHub CPS Network Service may already exist or service principal may not be available in this tenant"

echo
echo Assigning custom role to GitHub Actions API
. az role assignment create --assignee "$GITHUB_ACTIONS_API_ID" --role "$CUSTOM_ROLE_NAME" --scope "/subscriptions/$SUBSCRIPTION_ID" || echo "Warning: Role assignment for GitHub Actions API may already exist or service principal may not be available in this tenant"

echo
echo Create resource group $RESOURCE_GROUP_NAME at $AZURE_LOCATION
. az group create --name $RESOURCE_GROUP_NAME --location $AZURE_LOCATION

echo
echo Create NSG rules deployed with 'actions-nsg-deployment.bicep' file
. az deployment group create --resource-group $RESOURCE_GROUP_NAME --template-file ./actions-nsg-deployment.bicep --parameters location=$AZURE_LOCATION nsgName=$NSG_NAME

echo
echo Create vnet $VNET_NAME and subnet $SUBNET_NAME
. az network vnet create --resource-group $RESOURCE_GROUP_NAME --name $VNET_NAME --address-prefix $ADDRESS_PREFIX --subnet-name $SUBNET_NAME --subnet-prefixes $SUBNET_PREFIX

echo
echo Delegate subnet to GitHub.Network/networkSettings and apply NSG rules
. az network vnet subnet update --resource-group $RESOURCE_GROUP_NAME --name $SUBNET_NAME --vnet-name $VNET_NAME --delegations GitHub.Network/networkSettings --network-security-group $NSG_NAME

echo
echo Create network settings resource $NETWORK_SETTINGS_RESOURCE_NAME
. az resource create --resource-group $RESOURCE_GROUP_NAME --name $NETWORK_SETTINGS_RESOURCE_NAME --resource-type GitHub.Network/networkSettings --properties "{ \"location\": \"$AZURE_LOCATION\", \"properties\" : { \"subnetId\": \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/$SUBNET_NAME\", \"businessId\": \"$DATABASE_ID\" }}" --is-full-object --output table --query "{GitHubId:tags.GitHubId, name:name}" --api-version $API_VERSION

echo
echo To clean up and delete resources run the following commands:
echo "# Delete resource group and all resources:"
echo "az group delete --resource-group $RESOURCE_GROUP_NAME"
echo
echo "# Remove role assignments:"
echo "az role assignment delete --assignee $GITHUB_CPS_NETWORK_SERVICE_ID --role $CUSTOM_ROLE_NAME --scope /subscriptions/$SUBSCRIPTION_ID"
echo "az role assignment delete --assignee $GITHUB_ACTIONS_API_ID --role $CUSTOM_ROLE_NAME --scope /subscriptions/$SUBSCRIPTION_ID"
echo
echo "# Delete custom role definition:"
echo "az role definition delete --name $CUSTOM_ROLE_NAME"
echo
echo "# Clean up temporary files:"
echo "rm -f /tmp/github-actions-network-role.json"

echo
echo "Cleaning up temporary files..."
rm -f /tmp/github-actions-network-role.json

