# net-azure

## Azure Network Setup for GitHub Actions

This repository contains scripts to set up Azure network resources and RBAC permissions required for GitHub Actions to work with Azure hosted networks.

### Features

The `setup.sh` script automatically:

1. **Creates Azure network infrastructure:**
   - Resource group
   - Network Security Group (NSG) with required rules
   - Virtual network (VNet) and subnet
   - Network Settings resource for GitHub Enterprise

2. **Sets up Azure RBAC permissions:**
   - Creates a custom role with all required permissions for GitHub Actions
   - Assigns the role to GitHub service principals:
     - GitHub CPS Network Service (ID: 85c49807-809d-4249-86e7-192762525474)
     - GitHub Actions API (ID: 4435c199-c3da-46b9-a61d-76de3f2c9f82)

### Usage

1. Update the environment variables in `setup.sh` with your Azure configuration
2. Run the script: `./setup.sh`
3. The script will handle all resource creation and RBAC assignment automatically

### Cleanup

To remove all resources and role assignments, run the cleanup commands provided at the end of the script execution.

### Files

- `setup.sh` - Main setup script
- `github-actions-custom-role.json` - Custom RBAC role definition
- `actions-nsg-deployment.bicep` - NSG deployment template