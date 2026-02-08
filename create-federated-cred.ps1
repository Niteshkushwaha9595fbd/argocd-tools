# create-federated-cred.ps1
param(
  [string]$aadAppId = "a582e956-6fbd-4632-9d89-c56ecd8d0b9e",
  [string]$tenantId = "929fd68c-31c9-499d-bb45-56d96d7c8d9d"
)

# Login (interactive)


# Optional: set subscription if needed
# az account set --subscription "1c31cbbc-25c4-40cf-8e4e-44be901aa7ef"

# Create federated credential using a PowerShell here-string (reliable quoting)
az ad app federated-credential create --id $aadAppId --parameters @"
{
  "name": "agic-federation",
  "issuer": "https://sts.windows.net/$tenantId/",
  "subject": "system:serviceaccount:kube-system:agic-serviceaccount",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ -o json
