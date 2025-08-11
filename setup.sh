#!/bin/zsh

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
export AZURE_LOCATION=eastus
export SUBSCRIPTION_ID=633c6407-e4fe-4a17-9cc4-7c7e477a6d75
export RESOURCE_GROUP_NAME=azugh
export VNET_NAME=azuvnet
export SUBNET_NAME=azusubnet
export NSG_NAME=azunsg
export NETWORK_SETTINGS_RESOURCE_NAME=azusettings
export DATABASE_ID=413793
export API_VERSION=2024-04-02

# These are the default values. You can adjust your address and subnet prefixes.
export ADDRESS_PREFIX=10.0.0.0/16
export SUBNET_PREFIX=10.0.0.0/24
export TMPDIR=/data/data/com.termux/files/usr/tmp

# GitHub Actions service principal IDs
export GITHUB_CPS_NETWORK_SERVICE_ID=85c49807-809d-4249-86e7-192762525474
export GITHUB_ACTIONS_API_SERVICE_ID=4435c199-c3da-46b9-a61d-76de3f2c9f82
export CUSTOM_ROLE_NAME="GitHub Actions Network Service Role"
export ROLE_DEFINITION_FILE="./github-actions-network-role.json"

# Function to create custom role definition
create_custom_role() {
    local role_name="$1"
    local role_file="$2"
    local subscription_id="$3"
    
    echo "Creating custom role definition: $role_name"
    
    local tmpfile="$TMPDIR/role-definition.json"
    sed "s/SUBSCRIPTION_ID_PLACEHOLDER/$subscription_id/g" "$role_file" > "$tmpfile"
    
    if az role definition list --name "$role_name" --subscription "$subscription_id" --query "[].roleName" -o tsv | grep -q "^$role_name$"; then
        echo "Custom role '$role_name' already exists. Updating..."
        az role definition update --role-definition "$tmpfile"
    else
        echo "Creating new custom role '$role_name'..."
        az role definition create --role-definition "$tmpfile"
    fi
    
    rm -f "$tmpfile"
    
    echo "Custom role '$role_name' created/updated successfully"
}

# Function to assign role to service principal
assign_role_to_service_principal() {
    local role_name="$1"
    local service_principal_id="$2"
    local subscription_id="$3"
    local service_name="$4"
    
    echo "Assigning role '$role_name' to $service_name (ID: $service_principal_id)"
    
    # Check if role assignment already exists
    if az role assignment list --assignee "$service_principal_id" --role "$role_name" --scope "/subscriptions/$subscription_id" --query "[].principalId" -o tsv | grep -q "$service_principal_id"; then
        echo "Role assignment already exists for $service_name"
    else
        echo "Creating role assignment for $service_name..."
        az role assignment create \
            --assignee "$service_principal_id" \
            --role "$role_name" \
            --scope "/subscriptions/$subscription_id"
        echo "Role assigned successfully to $service_name"
    fi
}

# Function to setup RBAC permissions
setup_rbac_permissions() {
    echo
    echo "=== Setting up RBAC permissions for GitHub Actions service ==="
    
    # Create custom role definition
    create_custom_role "$CUSTOM_ROLE_NAME" "$ROLE_DEFINITION_FILE" "$SUBSCRIPTION_ID"
    
    # Assign role to GitHub CPS Network Service
    assign_role_to_service_principal "$CUSTOM_ROLE_NAME" "$GITHUB_CPS_NETWORK_SERVICE_ID" "$SUBSCRIPTION_ID" "GitHub CPS Network Service"
    
    # Assign role to GitHub Actions API
    assign_role_to_service_principal "$CUSTOM_ROLE_NAME" "$GITHUB_ACTIONS_API_SERVICE_ID" "$SUBSCRIPTION_ID" "GitHub Actions API"
    
    echo "RBAC permissions setup completed successfully"
}

# Function to cleanup RBAC permissions
cleanup_rbac_permissions() {
    echo
    echo "=== Cleaning up RBAC permissions ==="
    
    # Remove role assignments
    echo "Removing role assignment for GitHub CPS Network Service..."
    az role assignment delete \
        --assignee "$GITHUB_CPS_NETWORK_SERVICE_ID" \
        --role "$CUSTOM_ROLE_NAME" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" || echo "Role assignment not found or already removed"
    
    echo "Removing role assignment for GitHub Actions API..."
    az role assignment delete \
        --assignee "$GITHUB_ACTIONS_API_SERVICE_ID" \
        --role "$CUSTOM_ROLE_NAME" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" || echo "Role assignment not found or already removed"
    
    # Remove custom role definition
    echo "Removing custom role definition..."
    az role definition delete --name "$CUSTOM_ROLE_NAME" || echo "Custom role not found or already removed"
    
    echo "RBAC permissions cleanup completed"
}

echo
echo login to Azure
az login --output none

echo
echo set account context $SUBSCRIPTION_ID
az account set --subscription $SUBSCRIPTION_ID

echo
echo Register resource provider GitHub.Network
az provider register --namespace GitHub.Network

# Setup RBAC permissions for GitHub Actions service
setup_rbac_permissions

echo
echo Create resource group $RESOURCE_GROUP_NAME at $AZURE_LOCATION
az group create --name $RESOURCE_GROUP_NAME --location $AZURE_LOCATION

echo
echo Create NSG rules deployed with 'actions-nsg-deployment.bicep' file
az deployment group create --resource-group $RESOURCE_GROUP_NAME --template-file ./actions-nsg-deployment.bicep --parameters location=$AZURE_LOCATION nsgName=$NSG_NAME

echo
echo Create vnet $VNET_NAME and subnet $SUBNET_NAME
az network vnet create --resource-group $RESOURCE_GROUP_NAME --name $VNET_NAME --address-prefix $ADDRESS_PREFIX --subnet-name $SUBNET_NAME --subnet-prefixes $SUBNET_PREFIX

echo
echo Delegate subnet to GitHub.Network/networkSettings and apply NSG rules
az network vnet subnet update --resource-group $RESOURCE_GROUP_NAME --name $SUBNET_NAME --vnet-name $VNET_NAME --delegations GitHub.Network/networkSettings --network-security-group $NSG_NAME

echo
echo Create network settings resource $NETWORK_SETTINGS_RESOURCE_NAME
az resource create --resource-group $RESOURCE_GROUP_NAME --name $NETWORK_SETTINGS_RESOURCE_NAME --resource-type GitHub.Network/networkSettings --properties "{ \"location\": \"$AZURE_LOCATION\", \"properties\" : { \"subnetId\": \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/$SUBNET_NAME\", \"businessId\": \"$DATABASE_ID\" }}" --is-full-object --output table --query "{GitHubId:tags.GitHubId, name:name}" --api-version $API_VERSION

echo
echo To clean up and delete resources run the following commands:
echo "# Remove RBAC permissions:"
echo "# $(dirname "$0")/cleanup-rbac.sh"
echo "# Or manually run: cleanup_rbac_permissions"
echo
echo "# Remove resource group and all contained resources:"
echo "az group delete --resource-group $RESOURCE_GROUP_NAME"
echo
echo "# Note: The custom role definition will be automatically removed"
echo "# when cleaning up RBAC permissions, or you can remove it manually with:"
echo "# az role definition delete --name \"$CUSTOM_ROLE_NAME\""

