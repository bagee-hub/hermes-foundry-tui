# GitHub Actions Deployment Guide

This guide explains how to deploy the Hermes Foundry TUI agent to Azure AI Foundry using GitHub Actions (no local Docker required).

## Prerequisites

- GitHub repository: `https://github.com/glennc/hermes-foundry-tui`
- Azure subscription provisioned with `azd provision`
- Service principal created (see credentials below)

## Service Principal Credentials

A service principal has been created. The credentials are stored locally in `DEPLOYMENT_SUMMARY.md` (gitignored).

**⚠️ IMPORTANT: Never commit credentials to the repository. Use GitHub Secrets instead.**

## Setup Steps

### 1. Configure GitHub Secrets

Go to your GitHub repository settings and add the following secrets:

**Repository Settings → Secrets and variables → Actions → New repository secret**

Add these secrets (values are in your local `DEPLOYMENT_SUMMARY.md` file):

| Secret Name | Description |
|------------|-------------|
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_CLIENT_SECRET` | Service principal secret |
| `AZURE_ENV_NAME` | Environment name (e.g., `dev`) |
| `AZURE_LOCATION` | Azure region (e.g., `eastus2`) |

### 2. Push the Workflow File

The workflow file has been created at `.github/workflows/deploy-foundry.yml`.

Commit and push it:

```bash
git add .github/workflows/deploy-foundry.yml
git commit -m "Add GitHub Actions deployment workflow"
git push origin main
```

### 3. Configure Federated Identity (Recommended - More Secure)

Instead of using client secrets, you can use OpenID Connect (OIDC) for passwordless authentication:

```bash
# Get the service principal object ID
SP_OBJECT_ID=$(az ad sp show --id 04105e28-796c-4b0c-871c-e466a2f99372 --query id -o tsv)

# Add federated credential for GitHub Actions
az ad app federated-credential create \
  --id 04105e28-796c-4b0c-871c-e466a2f99372 \
  --parameters '{
    "name": "hermes-foundry-tui-github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:glennc/hermes-foundry-tui:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

If using federated identity, you can **remove** the `AZURE_CLIENT_SECRET` secret from GitHub.

### 4. Upload azd Environment State

The GitHub Actions workflow needs your azd environment configuration. You have two options:

#### Option A: Manual Upload (Simpler)

1. Go to GitHub repository → Settings → Secrets and variables → Actions
2. Add a new secret named `AZD_ENV_STATE`
3. Copy the contents of `.azure/dev/.env` and paste as the value

#### Option B: Use azd remote state (Better for teams)

```bash
# Configure azd to use remote state
azd config set alpha.remoteState on
azd env push
```

### 5. Trigger Deployment

#### Manual Trigger (Recommended for first deployment)

1. Go to GitHub repository → Actions
2. Select "Deploy to Azure AI Foundry" workflow
3. Click "Run workflow" → Select branch "main" → Click "Run workflow"

#### Automatic Trigger

The workflow automatically runs on:
- Push to `main` branch
- Changes to `agent/`, `third_party/hermes/`, or `infra/` directories

### 6. Monitor Deployment

1. Go to GitHub repository → Actions
2. Click on the running workflow
3. Expand the "Deploy to Azure" step to see progress

Deployment typically takes 5-10 minutes.

### 7. Get Deployment Endpoint

After successful deployment, get your Foundry endpoint:

```bash
azd env get-values | grep AZURE_FOUNDRY_PROJECT_ENDPOINT
```

Or from Azure Portal:
1. Go to Azure Portal → Resource Groups → `rg-dev`
2. Find the AI Foundry project resource
3. Copy the endpoint URL

## Testing the Deployed Agent

### Option 1: Connect TUI to Cloud Agent

Update your local TUI to connect to the deployed agent:

```bash
export HERMES_FOUNDRY_ENDPOINT="<your-foundry-endpoint>"
./scripts/run-foundry-tui.sh
```

### Option 2: Test via Azure AI Studio

1. Go to Azure AI Studio: https://ai.azure.com
2. Navigate to your project
3. Go to "Agents" section
4. Test the deployed agent

## Troubleshooting

### Workflow fails with "Resource not found"

Run `azd provision` locally first to ensure all Azure resources are created.

### Authentication errors

Verify all GitHub secrets are set correctly. Check the service principal has Contributor role:

```bash
az role assignment list --assignee 04105e28-796c-4b0c-871c-e466a2f99372 --all
```

### Build fails

Check the workflow logs for specific errors. Common issues:
- Missing dependencies in `requirements.txt`
- Dockerfile syntax errors
- Resource quota limits

## Alternative: Azure DevOps Pipeline

If you prefer Azure DevOps, create a pipeline with similar steps:

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - agent/*
      - third_party/hermes/*
      - infra/*

pool:
  vmImage: 'ubuntu-latest'

steps:
  - task: AzureCLI@2
    inputs:
      azureSubscription: 'your-service-connection'
      scriptType: 'bash'
      scriptLocation: 'inlineScript'
      inlineScript: |
        curl -fsSL https://aka.ms/install-azd.sh | bash
        azd deploy --no-prompt
```

## Cleanup

To delete the service principal when no longer needed:

```bash
az ad sp delete --id 04105e28-796c-4b0c-871c-e466a2f99372
```

## Next Steps

After successful deployment:
1. Configure monitoring and alerts
2. Set up custom domains (optional)
3. Configure scaling policies
4. Integrate with your applications

## Support

For issues:
- GitHub Issues: https://github.com/glennc/hermes-foundry-tui/issues
- Azure Support: https://aka.ms/azuresupport
