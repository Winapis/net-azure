#!/bin/bash

# This script creates the following resources in the specified subscription:
# - Resource group
# - Network Security Group rules
# - Virtual network (vnet) and subnet
# - Network Settings with specified subnet and GitHub Enterprisedatabase ID
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

# These are the default values. You can adjust your address and subnet prefixes.
export ADDRESS_PREFIX=10.0.0.0/16
export SUBNET_PREFIX=10.0.0.0/24

# GitHub service principals for RBAC assignment
export GITHUB_CPS_NETWORK_SERVICE_ID=85c49807-809d-4249-86e7-192762525474
export GITHUB_ACTIONS_API_ID=4435c199-c3da-46b9-a61d-76de3f2c9f82
export CUSTOM_ROLE_NAME="GitHub Actions Network Service Role"

# Function to create custom role definition
create_custom_role() {
    echo
    echo "Creating custom role definition for GitHub Actions network permissions..."
    
    # Replace placeholder in role definition file
    sed "s/SUBSCRIPTION_ID_PLACEHOLDER/$SUBSCRIPTION_ID/g" github-actions-custom-role.json > /tmp/github-actions-custom-role-temp.json
    
    # Check if role already exists
    if az role definition list --name "$CUSTOM_ROLE_NAME" --subscription $SUBSCRIPTION_ID --query "[].roleName" -o tsv | grep -q "$CUSTOM_ROLE_NAME"; then
        echo "Custom role '$CUSTOM_ROLE_NAME' already exists. Updating role definition..."
        az role definition update --role-definition /tmp/github-actions-custom-role-temp.json
    else
        echo "Creating new custom role '$CUSTOM_ROLE_NAME'..."
        az role definition create --role-definition /tmp/github-actions-custom-role-temp.json
    fi
    
    # Clean up temporary file
    rm -f /tmp/github-actions-custom-role-temp.json
}

# Function to assign role to service principal
assign_role_to_service_principal() {
    local service_principal_id=$1
    local service_name=$2
    
    echo
    echo "Assigning custom role to $service_name (ID: $service_principal_id)..."
    
    # Check if role assignment already exists
    if az role assignment list --assignee $service_principal_id --role "$CUSTOM_ROLE_NAME" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].principalId" -o tsv | grep -q "$service_principal_id"; then
        echo "Role assignment already exists for $service_name"
    else
        echo "Creating role assignment for $service_name..."
        az role assignment create \
            --assignee $service_principal_id \
            --role "$CUSTOM_ROLE_NAME" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
        echo "Role assignment created successfully for $service_name"
    fi
}

# Function to setup GitHub Actions RBAC permissions
setup_github_actions_rbac() {
    echo
    echo "=== Setting up GitHub Actions RBAC Permissions ==="
    
    # Create custom role
    create_custom_role
    
    # Assign role to GitHub service principals
    assign_role_to_service_principal $GITHUB_CPS_NETWORK_SERVICE_ID "GitHub CPS Network Service"
    assign_role_to_service_principal $GITHUB_ACTIONS_API_ID "GitHub Actions API"
    
    echo
    echo "GitHub Actions RBAC permissions setup completed successfully!"
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
echo "=== Setting up GitHub Actions RBAC permissions ==="
setup_github_actions_rbac

echo
echo "=== Setup completed successfully! ==="
echo
echo "To clean up and delete resources run the following commands:"
echo "# Delete resource group and all contained resources:"
echo "az group delete --resource-group $RESOURCE_GROUP_NAME"
echo
echo "# Remove role assignments for GitHub Actions service principals:"
echo "az role assignment delete --assignee $GITHUB_CPS_NETWORK_SERVICE_ID --role \"$CUSTOM_ROLE_NAME\" --scope \"/subscriptions/$SUBSCRIPTION_ID\""
echo "az role assignment delete --assignee $GITHUB_ACTIONS_API_ID --role \"$CUSTOM_ROLE_NAME\" --scope \"/subscriptions/$SUBSCRIPTION_ID\""
echo
echo "# Delete custom role definition:"
echo "az role definition delete --name \"$CUSTOM_ROLE_NAME\""

