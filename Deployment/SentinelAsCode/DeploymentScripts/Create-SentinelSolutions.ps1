<#
.SYNOPSIS
    Deploys Microsoft Sentinel Solutions and Analytical Rules to a specified Microsoft Sentinel workspace.

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
    An optional list of rule severities to include (e.g. High, Medium, Low).

.PARAMETER IsGov
    Specifies whether the script should target an Azure Government cloud.

.NOTES
    Author: noodlemctwoodle
    Version: 2.0
    Last Updated: 24/02/2025
    GitHub Repository: SentinelPublic

.EXAMPLE

    .\Deploy-Sentinel.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft Defender XDR", "Microsoft 365" -SeveritiesToInclude "High", "Medium"

    Deploys "Microsoft Defender XDR" and "Microsoft 365" Sentinel solutions while filtering analytical rules to include only "High" and "Medium" severity incidents.

.EXAMPLE
    .\Deploy-Sentinel.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft Defender XDR", "Microsoft 365" -SeveritiesToInclude "High", "Medium" -IsGov $true

    Deploys "Microsoft Defender XDR" and "Microsoft 365" Sentinel solutions while filtering analytical rules to include only "High" and "Medium" severity incidents in an Azure Government cloud environment.
#>

param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$Region,
    [Parameter(Mandatory = $true)][string[]]$Solutions,
    [Parameter(Mandatory = $false)][string[]]$SeveritiesToInclude = @("High", "Medium", "Low"),
    [Parameter(Mandatory = $false)][string]$IsGov = "false"
)

# 
$IsGov = ($IsGov -eq 'true' -or $IsGov -eq '1')

Write-Host "GovCloud Mode: $IsGov"

# 
if ($Solutions -isnot [array]) { $Solutions = @($Solutions) }
if ($SeveritiesToInclude -isnot [array]) { $SeveritiesToInclude = @($SeveritiesToInclude) }

# 
function Connect-ToAzure {
    # 
    $context = Get-AzContext
    
    # 
    if (!$context) {
        Connect-AzAccount -Environment AzureUSGovernment
        $context = Get-AzContext
    }
    
    return $context
}

# 
$context = Connect-ToAzure
$SubscriptionId = $context.Subscription.Id
Write-Host "Connected to Azure with Subscription: $SubscriptionId" -ForegroundColor Blue

# 
$serverUrl = if ($IsGov -eq $true) { 
    "https://management.usgovcloudapi.net"  # Azure Government API endpoint
} else { 
    "https://management.azure.com"          # Azure Public API endpoint
}

# 
$baseUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"

# 
$instanceProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($instanceProfile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)

# 
$authHeader = @{
    'Content-Type'  = 'application/json' 
    'Authorization' = 'Bearer ' + $token.AccessToken 
}

### Function: Deploy Solutions ###

#
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

        # 
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

        #  
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

        # 
        $installURL = "$serverUrl/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/Microsoft.Resources/deployments/$deploymentName"
        $installURL = $installURL + "?api-version=2021-04-01"

        # 
        $job = Start-Job -ScriptBlock {
            param ($installURL, $installBody, $authHeader, $deploymentName, $solutionDisplayName)
            try {
                Invoke-RestMethod -Uri $installURL -Method Put -Headers $authHeader -Body ($installBody | ConvertTo-Json -EnumsAsStrings -Depth 50 -EscapeHandling EscapeNonAscii) | Out-Null
                Write-Host "Deployment successful: $deploymentName" -ForegroundColor Green
            } catch {
                $ErrorResponse = $_
                $RawError = $ErrorResponse.ErrorDetails.Message
                Write-Error "ERROR: Deployment failed for solution: $solutionDisplayName (Deployment: $deploymentName)"
                if ($RawError) {
                    Write-Error "Azure API Error: $($RawError.Substring(0, [Math]::Min(300, $RawError.Length)))"
                }
            }
        } -ArgumentList $installURL, $installBody, $authHeader, $deploymentName, $deploySolution

        # 
        $jobs += [PSCustomObject]@{
            Job      = $job
            Solution = $deploySolution
        }
        # 
        Start-Sleep -Milliseconds 1000
    }

    # 
    $failedJobs = @()
    foreach ($jobObject in $jobs) {
        try {
            Receive-Job -Job $jobObject.Job -Wait -ErrorAction Stop
        } catch {
            $failedJobs += $jobObject
            Write-Warning "Deployment failed for solution: $($jobObject.Solution)"
        }
    }
    if ($failedJobs.Count -gt 0) {
        Write-Error "Some deployments failed. Please review logs."
        exit 1
    } else {
        Write-Host "All Sentinel solutions have been deployed." -ForegroundColor Blue
    }
}

### Function: Deploy Analytical Rules ###

#
function Deploy-AnalyticalRules {
    Write-Host "Waiting for Sentinel to finalize content updates before retrieving Analytical Rules..."
    Start-Sleep -Seconds 90  # Adjust if needed

    Write-Host "Fetching available Sentinel solutions..." -ForegroundColor Yellow
    $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=2024-03-01"
    
    # 
    try {
        $allSolutions = (Invoke-RestMethod -Method "Get" -Uri $solutionURL -Headers $authHeader).value
        Write-Host "Successfully fetched Sentinel solutions." -ForegroundColor Green
    } catch {
        Write-Error "Failed to fetch Sentinel solutions: $($_.Exception.Message)"
        return
    }

    #
    Write-Host "Fetching available Analytical Rule templates..." -ForegroundColor Yellow
    $ruleTemplateURL = "$baseUri/providers/Microsoft.SecurityInsights/contentTemplates?api-version=2023-05-01-preview"
    $ruleTemplateURL += "&%24filter=(properties%2FcontentKind%20eq%20'AnalyticsRule')"
    
    #
    try {
        $results = (Invoke-RestMethod -Uri $ruleTemplateURL -Method Get -Headers $authHeader).value
        Write-Host "Successfully fetched $($results.Count) Analytical Rule templates." -ForegroundColor Green
    } catch {
        Write-Error "Failed to fetch Analytical Rule templates: $($_.Exception.Message)"
        return
    }

    if ($null -eq $results -or $results.Count -eq 0) {
        Write-Error "No Analytical Rule templates found! Exiting."
        return
    }

    #
    $BaseAlertUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRules/"
    $BaseMetaURI = "$baseUri/providers/Microsoft.SecurityInsights/metadata/analyticsrule-"

    Write-Host "Severities to include: $SeveritiesToInclude" -ForegroundColor Magenta
    
    #
    foreach ($result in $results) {
        $displayName = $result.properties.mainTemplate.resources.properties[0].displayName
        $severity = $result.properties.mainTemplate.resources.properties[0].severity

        if ($SeveritiesToInclude.Count -eq 0 -or $SeveritiesToInclude.Contains($severity)) {

            #Write-Host "Deploying Analytical Rule: $displayName" -ForegroundColor Cyan

            # 
            if ($displayName -match "\[Deprecated\]") {
                Write-Warning "Skipping Deprecated Rule: $displayName"
                continue
            }

            #
            $templateVersion = $result.properties.mainTemplate.resources.properties[1].version
            $kind = $result.properties.mainTemplate.resources[0].kind
            $properties = $result.properties.mainTemplate.resources[0].properties
            $properties.enabled = $true

            # 
            $properties | Add-Member -NotePropertyName "alertRuleTemplateName" -NotePropertyValue $result.properties.mainTemplate.resources[0].name
            $properties | Add-Member -NotePropertyName "templateVersion" -NotePropertyValue $templateVersion

            # 
            if ($properties.PSObject.Properties.Name -contains "entityMappings") {
                if ($properties.entityMappings -isnot [System.Array]) {
                    $properties.entityMappings = @($properties.entityMappings)
                }
            }

            # 
            if ($properties.PSObject.Properties.Name -contains "requiredDataConnectors") {
                if ($properties.requiredDataConnectors -is [System.Array] -and $properties.requiredDataConnectors.Count -eq 1) {
                    $properties.requiredDataConnectors = $properties.requiredDataConnectors[0]
                }
            }

            # 
            if ($properties.PSObject.Properties.Name -contains "incidentConfiguration") {
                if ($properties.incidentConfiguration.PSObject.Properties.Name -contains "groupingConfiguration") {
                
                    #
                    if (-not $properties.incidentConfiguration.groupingConfiguration) {
                        $properties.incidentConfiguration | Add-Member -NotePropertyName "groupingConfiguration" -NotePropertyValue @{
                            matchingMethod = "AllEntities"
                            lookbackDuration = "PT1H"
                        }
                        Write-Host "DEBUG: Created missing groupingConfiguration with default values (matchingMethod='AllEntities', lookbackDuration='PT1H')" -ForegroundColor Cyan
                    } else {
                        # 
                        if (-not ($properties.incidentConfiguration.groupingConfiguration.PSObject.Properties.Name -contains "matchingMethod")) {
                            $properties.incidentConfiguration.groupingConfiguration | Add-Member -NotePropertyName "matchingMethod" -NotePropertyValue "AllEntities"
                            Write-Host "DEBUG: Added missing matchingMethod='AllEntities' to groupingConfiguration" -ForegroundColor Cyan
                        }

                        # 
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
                        }
                    }
                }
            }

            # 
            $body = @{
                "kind"       = $kind
                "properties" = $properties
            }

            #
            $guid = (New-Guid).Guid
            $alertUri = "$BaseAlertUri$guid" + "?api-version=2022-12-01-preview"
            
            #
            try {
                $jsonBody = $body | ConvertTo-Json -Depth 50 -Compress
                $verdict = Invoke-RestMethod -Uri $alertUri -Method Put -Headers $authHeader -Body $jsonBody
                Write-Host "Successfully deployed rule: $displayName" -ForegroundColor Green

                # 
                $solution = $allSolutions | Where-Object { 
                    ($_.properties.contentId -eq $result.properties.packageId) -or 
                    ($_.properties.packageId -eq $result.properties.packageId)
                } | Select-Object -First 1
                
                #
                if ($solution) {
                    $sourceName = $solution.properties.displayName
                    $sourceId = $solution.name
                } else {
                    $sourceName = "Unknown Solution"
                    $sourceId = "Unknown-ID"
                    Write-Warning "No matching solution found for: $displayName"
                }

                # 
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

                # 
                $metaUri = "$BaseMetaURI$($verdict.name)?api-version=2022-01-01-preview"
                Invoke-RestMethod -Uri $metaUri -Method Put -Headers $authHeader -Body ($metaBody | ConvertTo-Json -Depth 5 -Compress) | Out-Null

            #
            } catch {
                if ($_.ErrorDetails.Message -match "One of the tables does not exist") {
                    Write-Warning "Skipping $displayName due to missing tables in the environment."
                } elseif ($_.ErrorDetails.Message -match "The given column") {
                    Write-Warning "Skipping $displayName due to missing column in the query."
                } elseif ($_.ErrorDetails.Message -match "FailedToResolveScalarExpression|SemanticError") {
                    Write-Warning "Skipping $displayName due to an invalid expression in the query."
                } else {
                    Write-Error "Deployment failed for Analytical Rule: $displayName"
                    Write-Error "Azure API Error: $($_.ErrorDetails.Message)"
                }
            }
        }
    }
    Write-Host "All Analytical Rules have been deployed." -ForegroundColor Green
}

#  
Deploy-Solutions
Deploy-AnalyticalRules
