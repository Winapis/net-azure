#!/bin/bash

# Cleanup script for GitHub Actions RBAC permissions
# This script removes the custom role assignments and role definition
# created by the setup.sh script for GitHub Actions service principals.

# stop on failure
set -e

# Import environment variables (you may need to adjust these)
export SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-YOUR_SUBSCRIPTION_ID}
export GITHUB_CPS_NETWORK_SERVICE_ID=85c49807-809d-4249-86e7-192762525474
export GITHUB_ACTIONS_API_SERVICE_ID=4435c199-c3da-46b9-a61d-76de3f2c9f82
export CUSTOM_ROLE_NAME="GitHub Actions Network Service Role"

echo "=== GitHub Actions RBAC Cleanup Script ==="
echo "This script will remove the custom role assignments and role definition"
echo "for GitHub Actions service principals."
echo
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Custom Role Name: $CUSTOM_ROLE_NAME"
echo

# Confirm before proceeding
read -p "Do you want to proceed with the cleanup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo
echo "Logging into Azure..."
az login --output none

echo
echo "Setting account context to subscription $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

echo
echo "=== Cleaning up RBAC permissions ==="

# Remove role assignments
echo "Removing role assignment for GitHub CPS Network Service..."
az role assignment delete \
    --assignee "$GITHUB_CPS_NETWORK_SERVICE_ID" \
    --role "$CUSTOM_ROLE_NAME" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" 2>/dev/null || echo "Role assignment not found or already removed"

echo "Removing role assignment for GitHub Actions API..."
az role assignment delete \
    --assignee "$GITHUB_ACTIONS_API_SERVICE_ID" \
    --role "$CUSTOM_ROLE_NAME" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" 2>/dev/null || echo "Role assignment not found or already removed"

# Remove custom role definition
echo "Removing custom role definition..."
az role definition delete --name "$CUSTOM_ROLE_NAME" 2>/dev/null || echo "Custom role not found or already removed"

echo
echo "RBAC permissions cleanup completed successfully!"
echo "The GitHub Actions service principals no longer have the custom network permissions."