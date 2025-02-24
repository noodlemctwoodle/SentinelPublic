<#
.SYNOPSIS
    Deploys Microsoft Sentinel Solutions and Analytical Rules to a specified Azure Sentinel workspace.

.DESCRIPTION
    This PowerShell script automates the deployment of Microsoft Sentinel solutions and analytical rules
    from the Content Hub into an Azure Sentinel workspace. It ensures only relevant rules are deployed
    by filtering based on severity, handling missing tables, deprecated rules, and unsupported configurations.

.PARAMETER ResourceGroup
    The name of the Azure Resource Group where the Sentinel workspace is located.

.PARAMETER Workspace
    The name of the Sentinel (Log Analytics) workspace.

.PARAMETER Region
    The Azure region where the workspace is deployed.

.PARAMETER Solutions
    An array of Microsoft Sentinel solutions to deploy.

.PARAMETER SeveritiesToInclude
    An optional list of rule severities to include (e.g., High, Medium, Low).

.PARAMETER IsGov
    Specifies whether the script should target an Azure Government cloud.

.NOTES
    Author: noodlemctwoodle
    Version: 2.0
    Last Updated: 24/02/2025
    GitHub Repository: SentinelPublic

.EXAMPLE

    .\Create-SentinelSolutions.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft Defender XDR", "Microsoft 365" -SeveritiesToInclude "High", "Medium"

    Deploys "Microsoft Defender XDR" and "Microsoft 365" Sentinel solutions while filtering analytical rules to include only "High" and "Medium" severity incidents.

.EXAMPLE
    .\Create-SentinelSolutions.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft Defender XDR", "Microsoft 365" -SeveritiesToInclude "High", "Medium" -IsGov $true

    Deploys "Microsoft Defender XDR" and "Microsoft 365" Sentinel solutions while filtering analytical rules to include only "High" and "Medium" severity incidents in an Azure Government cloud environment.
#>

param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$Region,
    [Parameter(Mandatory = $true)][string[]]$Solutions,
    [Parameter(Mandatory = $false)][string[]]$SeveritiesToInclude = @("High", "Medium", "Low"),  # Default severities
    [Parameter(Mandatory = $false)][bool]$IsGov = $false
)

# Ensure parameters are always treated as arrays
if ($Solutions -isnot [array]) { $Solutions = @($Solutions) }
if ($SeveritiesToInclude -isnot [array]) { $SeveritiesToInclude = @($SeveritiesToInclude) }

# Function to authenticate with Azure
function Connect-ToAzure {
    # Retrieve the current Azure context
    $context = Get-AzContext
    
    # If no context exists, authenticate with Azure (for GovCloud if specified)
    if (!$context) {
        Connect-AzAccount -Environment AzureUSGovernment
        $context = Get-AzContext
    }
    
    return $context
}

# Establish Azure authentication and retrieve subscription details
$context = Connect-ToAzure
$SubscriptionId = $context.Subscription.Id
Write-Host "Connected to Azure with Subscription: $SubscriptionId" -ForegroundColor Blue

# Determine the appropriate API server URL based on the environment (GovCloud or Public)
$serverUrl = if ($IsGov -eq $true) { 
    "https://management.usgovcloudapi.net"  # Azure Government API endpoint
} else { 
    "https://management.azure.com"          # Azure Public API endpoint
}

# Construct the base URI for Sentinel API calls
$baseUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"

# Retrieve an authorization token for API requests
$instanceProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($instanceProfile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)

# Create the authentication header required for REST API calls
$authHeader = @{
    'Content-Type'  = 'application/json' 
    'Authorization' = 'Bearer ' + $token.AccessToken 
}

### Function: Deploy Solutions ###
function Deploy-Solutions {
    Write-Host "Fetching available Sentinel solutions..." -ForegroundColor Yellow
    
    $url = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=2024-03-01"

    try {
        $allSolutions = (Invoke-RestMethod -Method "Get" -Uri $url -Headers $authHeader).value
        Write-Host "Successfully fetched Sentinel solutions." -ForegroundColor Green
    } catch {
        Write-Error "ERROR: Failed to fetch Sentinel solutions: $($_.Exception.Message)"
        return
    }

    if ($null -eq $allSolutions -or $allSolutions.Count -eq 0) {
        Write-Error "ERROR: No Sentinel solutions found! Exiting."
        return
    }

    $jobs = @()
    foreach ($deploySolution in $Solutions) {
        $singleSolution = $allSolutions | Where-Object { $_.properties.displayName -eq $deploySolution }
        if ($null -eq $singleSolution) {
            Write-Warning "Skipping solution '$deploySolution' - Not found in Sentinel Content Hub."
            continue
        }

        Write-Host "Deploying solution: $deploySolution" -ForegroundColor Yellow

        # Ensure `api-version` is included when retrieving solution details
        $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages/$($singleSolution.name)?api-version=2024-03-01"

        try {
            $solution = (Invoke-RestMethod -Method "Get" -Uri $solutionURL -Headers $authHeader)
            if ($null -eq $solution) {
                Write-Warning "Failed to retrieve details for solution: $deploySolution"
                continue
            }
        } catch {
            Write-Error "Unable to retrieve solution details: $($_.Exception.Message)"
            continue
        }

        $packagedContent = $solution.properties.packagedContent

        # Ensure `api-version` is included in Content Templates requests
        foreach ($resource in $packagedContent.resources) { 
            if ($null -ne $resource.properties.mainTemplate.metadata.postDeployment) { 
                $resource.properties.mainTemplate.metadata.postDeployment = $null 
            } 
        }

        $installBody = @{
            "properties" = @{
                "parameters" = @{
                    "workspace"          = @{"value" = $Workspace }
                    "workspace-location" = @{"value" = $Region }
                }
                "template"   = $packagedContent
                "mode"       = "Incremental"
            }
        }

        $deploymentName = "allinone-$($solution.name)".Substring(0, [Math]::Min(64, ("allinone-$($solution.name)").Length))

        # Ensure `api-version` is correctly formatted in the URL
        $installURL = "$serverUrl/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/Microsoft.Resources/deployments/$deploymentName"
        $installURL = $installURL + "?api-version=2021-04-01"

        #Write-Host "Starting deployment: $deploymentName"

        # Start deployment in parallel
        $job = Start-Job -ScriptBlock {
            param ($installURL, $installBody, $authHeader, $deploymentName)
            try {
                Invoke-RestMethod -Uri $installURL -Method Put -Headers $authHeader -Body ($installBody | ConvertTo-Json -EnumsAsStrings -Depth 50 -EscapeHandling EscapeNonAscii) | Out-Null
                Write-Host "Deployment successful: $deploymentName" -ForegroundColor Green
            } catch {
                $ErrorResponse = $_
                $RawError = $ErrorResponse.ErrorDetails.Message

                Write-Error "ERROR: Deployment failed for: $deploymentName"

                # Print only the first 300 characters of the error message for pipeline readability
                if ($RawError) {
                    Write-Error "Azure API Error: $($RawError.Substring(0, [Math]::Min(300, $RawError.Length)))"
                }

                # Save full response to log file for debugging
                $RawError | Out-File -FilePath "SentinelDeploymentError.log" -Append
            }
        } -ArgumentList $installURL, $installBody, $authHeader, $deploymentName

        $jobs += $job
        Start-Sleep -Milliseconds 250  # Prevent Azure API throttling
    }

    # Wait for all deployments to complete
    $jobs | ForEach-Object { Receive-Job -Job $_ -Wait }
    Write-Host "All Sentinel solutions have been deployed." -ForegroundColor Blue
}


### Function: Deploy Analytical Rules ###
function Deploy-AnalyticalRules {
    Write-Host "Fetching available Analytical Rule templates..." -ForegroundColor Yellow

    # Ensure `api-version` is included in the API request
    $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentTemplates?api-version=2023-05-01-preview"
    $solutionURL += "&%24filter=(properties%2FcontentKind%20eq%20'AnalyticsRule')"

    try {
        $results = (Invoke-RestMethod -Uri $solutionURL -Method Get -Headers $authHeader).value
        Write-Host "Successfully fetched Analytical Rule templates." -ForegroundColor Green
    } catch {
        Write-Error "ERROR: Failed to fetch Analytical Rule templates: $($_.Exception.Message)"
        return
    }

    if ($null -eq $results -or $results.Count -eq 0) {
        Write-Error "ERROR: No Analytical Rule templates found! Exiting."
        return
    }

    $BaseAlertUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRules/"
    $BaseMetaURI = "$baseUri/providers/Microsoft.SecurityInsights/metadata/analyticsrule-"

    Write-Host "Severities to include: $SeveritiesToInclude" -ForegroundColor Magenta

    foreach ($result in $results) {
        $severity = $result.properties.mainTemplate.resources.properties[0].severity

        if ($SeveritiesToInclude.Contains($severity)) {
            $displayName = $result.properties.mainTemplate.resources.properties[0].displayName
            
            # **Skip deprecated rules**
            if ($displayName -match "\[Deprecated\]") {
                Write-Warning "Skipping Deprecated Rule: $displayName"
                continue
            }

            #Write-Host "Deploying Analytical Rule: $displayName"

            $templateVersion = $result.properties.mainTemplate.resources.properties[1].version

            # Extract kind from the template
            if ($result.properties.mainTemplate.resources[0].kind) {
                $kind = $result.properties.mainTemplate.resources[0].kind
            } elseif ($result.properties.mainTemplate.resources.kind) {
                $kind = $result.properties.mainTemplate.resources.kind
            } else {
                Write-Error "ERROR: Unable to determine kind for $displayName"
                continue
            }

            # Get the properties and enable the rule
            $properties = $result.properties.mainTemplate.resources[0].properties
            $properties.enabled = $true

            # Add linking fields
            $properties | Add-Member -NotePropertyName "alertRuleTemplateName" -NotePropertyValue $result.properties.mainTemplate.resources[0].name
            $properties | Add-Member -NotePropertyName "templateVersion" -NotePropertyValue $result.properties.mainTemplate.resources[1].properties.version

            # Ensure entityMappings is an array
            if ($properties.PSObject.Properties.Name -contains "entityMappings") {
                if ($properties.entityMappings -isnot [System.Array]) {
                    $properties.entityMappings = @($properties.entityMappings)
                }
            }

            # Ensure requiredDataConnectors is an object
            if ($properties.PSObject.Properties.Name -contains "requiredDataConnectors") {
                if ($properties.requiredDataConnectors -is [System.Array] -and $properties.requiredDataConnectors.Count -eq 1) {
                    $properties.requiredDataConnectors = $properties.requiredDataConnectors[0]
                }
            }

            # Fix Grouping Configuration 
            if ($properties.PSObject.Properties.Name -contains "incidentConfiguration") {
                if ($properties.incidentConfiguration.PSObject.Properties.Name -contains "groupingConfiguration") {
                    
                    if (-not $properties.incidentConfiguration.groupingConfiguration) {
                        # If groupingConfiguration is missing, create it with default values
                        $properties.incidentConfiguration | Add-Member -NotePropertyName "groupingConfiguration" -NotePropertyValue @{
                            matchingMethod = "AllEntities"
                            lookbackDuration = "PT1H"
                        }
                        Write-Host "DEBUG: Created missing groupingConfiguration with default values (matchingMethod='AllEntities', lookbackDuration='PT1H')" -ForegroundColor Cyan
                    } else {
                        # If matchingMethod is missing, set default
                        if (-not ($properties.incidentConfiguration.groupingConfiguration.PSObject.Properties.Name -contains "matchingMethod")) {
                            $properties.incidentConfiguration.groupingConfiguration | Add-Member -NotePropertyName "matchingMethod" -NotePropertyValue "AllEntities"
                            Write-Host "DEBUG: Added missing matchingMethod='AllEntities' to groupingConfiguration" -ForegroundColor Cyan
                        }
            
                        # Handle lookback Duration formatting
                        if ($properties.incidentConfiguration.groupingConfiguration.PSObject.Properties.Name -contains "lookbackDuration") {
                            $lookbackDuration = $properties.incidentConfiguration.groupingConfiguration.lookbackDuration
                            if ($lookbackDuration -match "^(\d+)(h|d|m)$") {
                                $timeValue = $matches[1]
                                $timeUnit = $matches[2]
                                switch ($timeUnit) {
                                    "h" { $isoDuration = "PT${timeValue}H" }
                                    "d" { $isoDuration = "P${timeValue}D" }
                                    "m" { $isoDuration = "PT${timeValue}M" }
                                }
                                $properties.incidentConfiguration.groupingConfiguration.lookbackDuration = $isoDuration
                                Write-Host "DEBUG: Converted lookbackDuration '$lookbackDuration' to ISO 8601 format: '$isoDuration'" -ForegroundColor Cyan
                            }
                        } else {
                            # If lookbackDuration is missing, set default
                            $properties.incidentConfiguration.groupingConfiguration | Add-Member -NotePropertyName "lookbackDuration" -NotePropertyValue "PT1H"
                            Write-Host "DEBUG: Added missing lookbackDuration='PT1H' to groupingConfiguration" -ForegroundColor Cyan
                        }
                    }
            
                    # Final Debugging Output
                    Write-Host "DEBUG: Final groupingConfiguration:" -ForegroundColor Cyan
                    Write-Host ($properties.incidentConfiguration.groupingConfiguration | ConvertTo-Json -Depth 10)
                }
            }

            # Create JSON body based on rule type
            $body = @{
                "kind"       = $kind
                "properties" = $properties
            }

            $guid = (New-Guid).Guid
            $alertUri = "$BaseAlertUri$guid" + "?api-version=2022-12-01-preview"

            #Write-Host "Attempting to create rule: $displayName"

            try {
                $jsonBody = $body | ConvertTo-Json -Depth 50 -Compress
                $verdict = Invoke-RestMethod -Uri $alertUri -Method Put -Headers $authHeader -Body $jsonBody
                Write-Host "Successfully deployed rule: $displayName" -ForegroundColor Green

                # Extract source details from `allSolutions`
                $solution = $allSolutions.properties | Where-Object -Property "contentId" -Contains $result.properties.packageId
                $sourceName = if ($solution -and $solution.PSObject.Properties.Name -contains "source") {
                    $solution.source.name
                } else {
                    "Unknown Source"
                }
                $sourceId = if ($solution -and $solution.PSObject.Properties.Name -contains "sourceId") {
                    $solution.source.sourceId
                } else {
                    "Unknown-ID"
                }

                $metaBody = @{
                    "apiVersion" = "2022-01-01-preview"
                    "name"       = "analyticsrule-" + $verdict.name
                    "type"       = "Microsoft.OperationalInsights/workspaces/providers/metadata"
                    "id"         = $null
                    "properties" = @{
                        "contentId" = $result.properties.mainTemplate.resources[0].name
                        "parentId"  = $verdict.id
                        "kind"      = "AnalyticsRule"
                        "version"   = $templateVersion
                        "source"    = @{
                            "kind"     = "Solution"
                            "name"     = $sourceName
                            "sourceId" = $sourceId
                        }
                    }
                }

                $metaUri = "$BaseMetaURI$($verdict.name)?api-version=2022-01-01-preview"
                Invoke-RestMethod -Uri $metaUri -Method Put -Headers $authHeader -Body ($metaBody | ConvertTo-Json -Depth 5 -Compress) | Out-Null
                #Write-Output "Metadata update completed for rule: $displayName"

            } catch {
                if ($_.ErrorDetails.Message -match "One of the tables does not exist") {
                    Write-Warning "Skipping $displayName due to missing tables in the environment."
                } elseif ($_.ErrorDetails.Message -match "The given column") {
                    Write-Warning "Skipping $displayName due to missing column in the query."
                } elseif ($_.ErrorDetails.Message -match "FailedToResolveScalarExpression|SemanticError") {
                    Write-Warning "Skipping $displayName due to an invalid expression in the query."
                } else {
                    Write-Error "ERROR: Deployment failed for Analytical Rule: $displayName"
                    Write-Error "Azure API Error: $($_.ErrorDetails.Message)"
                }
            }
        }
    }

    Write-Host "All Analytical Rules have been deployed." -ForegroundColor Green
}

# Execution Functions 
Deploy-Solutions
Deploy-AnalyticalRules