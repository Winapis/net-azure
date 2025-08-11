# Azure RBAC Permissions for GitHub Actions

# Adding permissions for GitHub CPS Network Service
az role assignment create --assignee 85c49807-809d-4249-86e7-192762525474 --role "Network Contributor" --scope "/subscriptions/{subscription-id}"

# Adding permissions for GitHub Actions API
az role assignment create --assignee 4435c199-c3da-46b9-a61d-76de3f2c9f82 --role "Contributor" --scope "/subscriptions/{subscription-id}"

# Including all Network, Resources permissions for GitHub Actions service
# Add specific commands here as needed
