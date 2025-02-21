# Sentinel-Deployment-CI

## Overview

This repository contains the necessary scripts and templates to deploy Microsoft Sentinel infrastructure and configure alert rules using Azure DevOps CI/CD pipelines.

## Repository Structure

- `azure-pipelines.yml`: Azure DevOps pipeline configuration file.
- `Deployment/`: Directory containing Bicep templates for deploying resources.
  - `main.bicep`: Main Bicep template for deploying the resource group and Sentinel.
  - `sentinel.bicep`: Bicep template for deploying Log Analytics workspace and enabling Microsoft Sentinel.
- `DeploymentScripts/`: Directory containing PowerShell scripts for additional configurations.
  - `Create-NewSolutionAndRulesFromList.ps1`: Script to deploy Sentinel solutions and configure alert rules.
- `README.md`: This file.

## Prerequisites

- Azure subscription with appropriate permissions.
- Azure DevOps account.
- Service Principal for Azure authentication.
- PowerShell with Az modules installed.

## Setup Instructions

1. Clone this repository to your local machine.
2. Update the `azure-pipelines.yml` file with your Azure subscription details and resource names.
3. Commit and push your changes to the repository.

## Pipeline Variables

The following variables need to be set in your Azure DevOps pipeline:

- `$(clientId)`: The client ID of the Azure Service Principal.
- `$(clientSecret)`: The client secret of the Azure Service Principal.
- `$(DailyQuota)`: The daily quota for the Log Analytics workspace.
- `$(Region)`: The Azure region where resources will be deployed.
- `$(ResourceGroup)`: The name of the resource group.
- `$(tenantId)`: The tenant ID of the Azure Service Principal.
- `$(WorkspaceName)`: The name of the Log Analytics workspace.

## Pipeline Stages

### DeployBicep

This stage deploys the Microsoft Sentinel infrastructure using Bicep templates.

### EnableSentinelContentHub

This stage enables Sentinel solutions and configures alert rules. It runs only if the previous stage succeeds.

## Running the Pipeline

1. Navigate to your Azure DevOps project.
2. Create a new pipeline and select this repository.
3. Run the pipeline to deploy the Sentinel infrastructure and configure alert rules.

## Troubleshooting

- Ensure that the Service Principal has the necessary permissions to deploy resources.
- Verify that the Azure subscription and resource group names are correct.
- Check the pipeline logs for any errors and resolve them accordingly.

## Contributing

Contributions are welcome! Please submit a pull request with your changes.

## License

This project is licensed under the MIT License.