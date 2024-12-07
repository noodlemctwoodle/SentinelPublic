#requires -Version 7.0
#requires -Module Az.Accounts

<#
.SYNOPSIS
    Logic App ARM Template Export Script

.DESCRIPTION
    This script helps you select and export Logic Apps (including Sentinel Playbooks)
    as ARM templates. It guides you through selecting a tenant, subscription, resource group,
    and one or more Logic Apps. It can optionally generate templates suitable for gallery deployment
    and can update the required Az modules.

    It also allows you to change the default export location for the generated templates,
    and ensures you have both the Az.Accounts module and Microsoft.PowerShell.ConsoleGuiTools module
    installed, prompting you to install them if not found.

    This script is designed to run on PowerShell 7 or later, and is compatible with 
    Windows, macOS, and Linux environments.

.AUTHOR
    noodlemctwoodle

    Thanks to ThijsLecomte for Playbook-ARM-Template-Generator script, which was used as a reference.

.VERSION
    1.0.0

.NOTES
    Requirements:
      - PowerShell 7.0 or higher
      - Will prompt to install Az.Accounts module if missing.
      - Will prompt to install Microsoft.PowerShell.ConsoleGuiTools module if missing.
    This script leverages Out-ConsoleGridView, which is provided by ConsoleGuiTools.

    Run this script in a PowerShell 7+ terminal that supports ANSI colors for best experience.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TenantId
)

# Define the default folder where outputs will be saved.
$defaultExportFolder = Join-Path $PWD "Exports"

Write-Host "************************************************************" -ForegroundColor Green
Write-Host "*          Logic App ARM Template Export Script             *" -ForegroundColor Green
Write-Host "************************************************************" -ForegroundColor Green
Write-Host "This script will help you select and export Logic Apps as ARM templates." -ForegroundColor Green
Write-Host "By default, the output will be saved to:" -ForegroundColor Green
Write-Host "`t$defaultExportFolder" -ForegroundColor Green
Write-Host "You can choose to change this location if desired." -ForegroundColor Green
Write-Host "Running on PowerShell 7+, multi-platform compatible." -ForegroundColor Green
Write-Host "************************************************************" -ForegroundColor Green
Write-Host ""

# Check if Az.Accounts is installed
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "The Az.Accounts module is required to connect to Azure and manage subscriptions."

    $AzAccountsQuestion = "Do you want to install Az.Accounts now?"
    $AzAccountsChoices = New-Object System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]
    $AzAccountsChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', 'Install the Az.Accounts module'))
    $AzAccountsChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', 'Do not install and exit'))

    $AzAccountsDecision = $Host.UI.PromptForChoice(
        "Install Az.Accounts",
        $AzAccountsQuestion,
        $AzAccountsChoices,
        1
    )

    if ($AzAccountsDecision -eq 0) {
        # User chose to install the module
        try {
            Install-Module Az.Accounts -Scope CurrentUser -Force
            Import-Module Az.Accounts -ErrorAction Stop
            Write-Host "Az.Accounts module installed successfully."
        } catch {
            Write-Host "Failed to install Az.Accounts: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Exiting..."
            exit
        }
    } else {
        # User chose not to install, exit the script
        Write-Host "Cannot proceed without Az.Accounts. Exiting..."
        exit
    }
} else {
    # Module is already installed, just import it
    Import-Module Az.Accounts -ErrorAction SilentlyContinue
}

# Check if Microsoft.PowerShell.ConsoleGuiTools is installed, if not prompt to install
if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.ConsoleGuiTools)) {
    Write-Host "The Microsoft.PowerShell.ConsoleGuiTools module is required for Out-ConsoleGridView."

    $ConsoleGuiToolsQuestion = "Do you want to install Microsoft.PowerShell.ConsoleGuiTools now?"
    $ConsoleGuiToolsChoices = New-Object System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]
    $ConsoleGuiToolsChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', 'Install the ConsoleGuiTools module'))
    $ConsoleGuiToolsChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', 'Do not install and exit'))

    $ConsoleGuiToolsDecision = $Host.UI.PromptForChoice(
        "Install ConsoleGuiTools",
        $ConsoleGuiToolsQuestion,
        $ConsoleGuiToolsChoices,
        1
    )

    if ($ConsoleGuiToolsDecision -eq 0) {
        # User chose to install the module
        try {
            Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser -Force
            Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction Stop
            Write-Host "Microsoft.PowerShell.ConsoleGuiTools module installed successfully."
        } catch {
            Write-Host "Failed to install Microsoft.PowerShell.ConsoleGuiTools: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Exiting..."
            exit
        }
    } else {
        # User chose not to install, exit the script
        Write-Host "Cannot proceed without Microsoft.PowerShell.ConsoleGuiTools. Exiting..."
        exit
    }
} else {
    # Module is already installed, just import it
    Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction SilentlyContinue
}

# Prompt user if they want to change the export location from the default.
$ChangeLocationQuestion = "Would you like to change the default export location?"
$ChangeLocationChoices = New-Object System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]
$ChangeLocationChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', 'Change the export folder location'))
$ChangeLocationChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', 'Use the default export folder location'))

$ChangeLocationDecision = $Host.UI.PromptForChoice(
    "Change Export Location",
    $ChangeLocationQuestion,
    $ChangeLocationChoices,
    1
)

if ($ChangeLocationDecision -eq 0) {
    # User chose to change the export location.
    # We'll start from the user's home directory and let them pick a subdirectory via Out-ConsoleGridView.
    $startingPath = $HOME
    Write-Host "Selecting export folder from directories under: $startingPath"
    $directories = Get-ChildItem -Directory -Path $startingPath | Select-Object Name,FullName

    # Present directories in a grid view for selection.
    $selectedDirectory = $directories | Out-ConsoleGridView -Title "Select Export Folder (Press ENTER when done)" -OutputMode Single

    if (-not $selectedDirectory) {
        # If no directory was selected, fall back to the default export folder.
        Write-Host "No directory selected. Using default location: $defaultExportFolder" -ForegroundColor Yellow
        $exportFolder = $defaultExportFolder
    } else {
        # User selected a directory; use it as the export folder.
        Write-Host "Selected directory: $($selectedDirectory.FullName)" -ForegroundColor Green
        $exportFolder = $selectedDirectory.FullName

        # If the directory doesn't exist, try to create it.
        if (-not (Test-Path $exportFolder)) {
            Write-Host "Directory does not exist. Attempting to create $exportFolder" -ForegroundColor Yellow
            try {
                New-Item -ItemType Directory -Path $exportFolder -Force | Out-Null
                Write-Host "Directory created: $exportFolder" -ForegroundColor Green
            } catch {
                # If directory creation fails, revert to default export folder.
                Write-Host "Failed to create directory at '$exportFolder'. Using default location." -ForegroundColor Red
                $exportFolder = $defaultExportFolder
            }
        }
    }
} else {
    # User chose not to change the location, use the default export folder.
    $exportFolder = $defaultExportFolder
}

# Display the final chosen export folder path.
Write-Host "Final export folder: $exportFolder" -ForegroundColor Green

# Ensure the export folder actually exists; create it if not.
#if (-not (Test-Path $exportFolder)) {
#    New-Item -Path $exportFolder -ItemType Directory | Out-Null
#}

# A simple logging function to write messages with severity.
Function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Severity = 'Information'
    )
    Write-Host "[$Severity] $Message"
}

# Import the Az.Accounts module to allow Azure login and context commands.
Import-Module Az.Accounts -ErrorAction Stop

# Prompt the user whether they want to generate the ARM template with gallery-specific configurations.
$TemplateGalleryQuestion = "Generate ARM Template for Gallery?"
$TemplateGalleryChoices = New-Object System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]
$TemplateGalleryChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', 'Generate the ARM template with gallery-specific configurations'))
$TemplateGalleryChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', 'Generate a standard ARM template without gallery-specific configurations'))

$TemplateGalleryDecision = $Host.UI.PromptForChoice(
    "Gallery Template Generation",
    $TemplateGalleryQuestion,
    $TemplateGalleryChoices,
    1
)
$GenerateForGallery = $TemplateGalleryDecision -eq 0

# Prompt user if they want to update Az modules to latest versions.
$UpdateModulesQuestion = "Do you want to update required Az Modules to latest version?"
$UpdateModulesChoices = New-Object System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]
$UpdateModulesChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', 'Attempt to update Az modules to the latest version'))
$UpdateModulesChoices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', 'Use currently installed Az modules'))

$UpdateModulesDecision = $Host.UI.PromptForChoice(
    "Update Az Modules",
    $UpdateModulesQuestion,
    $UpdateModulesChoices,
    1
)
$UpdateAzModules = $UpdateModulesDecision -eq 0

# Function to update Az modules if requested.
Function Update-AzModulesIfNeeded {
    param(
        [bool]$ShouldUpdate
    )
    if ($ShouldUpdate) {
        Write-Host "Updating Az Modules to the latest version..."
        Try {
            Install-Module Az -Scope CurrentUser -Force -ErrorAction Stop
            Import-Module Az -Force -ErrorAction Stop
            Write-Host "Az Modules successfully updated."
        }
        catch {
            Write-Host "Failed to update Az Modules: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Skipping Az Module update."
    }
}

# Update Az modules if user chose to do so.
Update-AzModulesIfNeeded -ShouldUpdate:$UpdateAzModules

# If TenantId not supplied, let the user select the tenant.
if (-not $TenantId) {
    Write-Host "Retrieving available tenants..."
    $tenants = Get-AzTenant
    if ($tenants.Count -gt 1) {
        Write-Host "Select Tenant:"
        $selectedTenant = $tenants | Out-ConsoleGridView -Title "Select Tenant" -OutputMode Single
        if (-not $selectedTenant) {
            Write-Host "No Tenant selected. Exiting..."
            exit
        }
        $TenantId = $selectedTenant.TenantId
    } else {
        # Only one tenant found, use it automatically.
        $TenantId = $tenants[0].TenantId
    }
}

Write-Host "Connecting to Azure with TenantId: $TenantId..."
Connect-AzAccount -Tenant $TenantId | Out-Null

# Let the user select a subscription from the available subscriptions.
Write-Host "Retrieving subscriptions..."
$subscriptions = Get-AzSubscription -TenantId $TenantId
if (-not $subscriptions) {
    Write-Host "No subscriptions found."
    exit
}

Write-Host "Select Subscription:"
$selectedSubscription = $subscriptions | Select-Object Name, SubscriptionId, State |
    Out-ConsoleGridView -Title "Select Subscription" -OutputMode Single
if (-not $selectedSubscription) {
    Write-Host "No Subscription selected. Exiting..."
    exit
}

# Set the context to the selected subscription.
$null = Set-AzContext -SubscriptionId $selectedSubscription.SubscriptionId -Tenant $TenantId

# Let the user select a Resource Group.
Write-Host "Retrieving Resource Groups for subscription: $($selectedSubscription.Name)"
$resourceGroups = Get-AzResourceGroup
if (-not $resourceGroups) {
    Write-Host "No Resource Groups found in this subscription."
    exit
}

Write-Host "Select Resource Group:"
$selectedResourceGroup = $resourceGroups | Select-Object ResourceGroupName, Location | Out-ConsoleGridView -Title "Select Resource Group" -OutputMode Single
if (-not $selectedResourceGroup) {
    Write-Host "No Resource Group selected. Exiting..."
    exit
}

# Retrieve all Logic Apps (workflows) in the chosen Resource Group.
Write-Host "Retrieving Logic Apps in Resource Group: $($selectedResourceGroup.ResourceGroupName)..."
$logicApps = Get-AzResource -ResourceGroupName $selectedResourceGroup.ResourceGroupName -ResourceType "Microsoft.Logic/workflows" -ExpandProperties

if (-not $logicApps) {
    Write-Host "No Logic Apps found in Resource Group '$($selectedResourceGroup.ResourceGroupName)'."
    exit
}

Write-Host "Use arrow keys to navigate, spacebar to select, and Enter to confirm your selection."
Write-Host "Press 'q' in the console grid view to exit without selection."

# Let the user select one or multiple Logic Apps to export.
$selectedLogicApps = $logicApps |
    Select-Object ResourceGroupName, Name, Location, @{Name='Kind';Expression={$_.Properties.kind}}, @{Name='State';Expression={$_.Properties.state}} |
    Out-ConsoleGridView -Title "Select Logic Apps to Export as ARM Templates (Press ENTER when done)"

if (-not $selectedLogicApps) {
    Write-Host "No Logic Apps selected. Exiting..."
    exit
}

# Setup variables for ARM template generation.
$armHostUrl = "https://management.azure.com"
$tokenToUse = (Get-AzAccessToken).Token
$PlaybookARMParameters = [ordered]@{}
$templateVariables = [ordered]@{}
$apiConnectionResources = New-Object System.Collections.Generic.List[Object]

# Function to fix JSON indentation for better readability.
Function FixJsonIndentation ($jsonOutput) {
    Try {
        $currentIndent = 0
        $tabSize = 4
        $lines = $jsonOutput.Split([Environment]::NewLine)
        $newString = ""
        foreach ($line in $lines) {
            if ($line.Trim() -eq "") {
                continue
            }

            # If line ends with ] or }, reduce indent first.
            if ($line -match "[\]\}],?\s*$") {
                $currentIndent -= 1
            }

            # Add current line with the right indent.
            if ($newString -eq "") {
                $newString = $line
            } else {
                $spaces = ""
                $matchFirstChar = [regex]::Match($line, '[^\s]+')
                $totalSpaces = $currentIndent * $tabSize
                if ($totalSpaces -gt 0) {
                    $spaces = " " * $totalSpaces
                }
                $newString += [Environment]::NewLine + $spaces + $line.Substring($matchFirstChar.Index)
            }

            # If line ends with { or [, increase indent.
            if ($line -match "[\[{]\s*$") {
                $currentIndent += 1
            }
        }
        return $newString
    }
    catch {
        Write-Log -Message "Error occurred in FixJsonIndentation :$($_)" -Severity Error
    }
}

# Function to build the full ARM resource ID for the playbook (logic app).
Function BuildPlaybookArmId() {
    Try {
        if ($PlaybookSubscriptionId -and $PlaybookResourceGroupName -and $PlaybookResourceName) {
            return "/subscriptions/$PlaybookSubscriptionId/resourceGroups/$PlaybookResourceGroupName/providers/Microsoft.Logic/workflows/$PlaybookResourceName"
        }
    }
    catch {
        Write-Log -Message "Playbook ARM id parameters are required: $($_)" -Severity Error
    }
}

# Function to send a GET call to ARM using REST.
Function SendArmGetCall($relativeUrl) {
    $authHeader = @{
        'Authorization'='Bearer ' + $tokenToUse
    }

    $absoluteUrl = $armHostUrl+$relativeUrl
    Try {
        $result = Invoke-RestMethod -Uri $absoluteUrl -Method Get -Headers $authHeader
        return $result
    }
    catch {
        Write-Log -Message $($_.Exception.Response.StatusCode.value__) -Severity Error
        Write-Log -Message $($_.Exception.Response.StatusDescription) -Severity Error
    } 
}

# Function to retrieve the playbook resource and adjust it for ARM template export.
Function GetPlaybookResource() {
    Try {    
        $playbookArmIdToUse = BuildPlaybookArmId
        $playbookResource = SendArmGetCall -relativeUrl "$($playbookArmIdToUse)?api-version=2017-07-01"

        # Add a parameter for the playbook name to the ARM template.
        $PlaybookARMParameters.Add("PlaybookName", [ordered] @{
            "defaultValue"= $playbookResource.Name
            "type"= "string"
        })

        # If generating for gallery, add specific tags, metadata, and ensure SystemAssigned identity.
        if ($GenerateForGallery) {
            if (!("tags" -in $playbookResource.PSobject.Properties.Name)) {
                Add-Member -InputObject $playbookResource -Name "tags" -Value @() -MemberType NoteProperty -Force
            }

            if (!$playbookResource.tags) {
                $playbookResource.tags = [ordered] @{
                    "hidden-SentinelTemplateName"= $playbookResource.name
                    "hidden-SentinelTemplateVersion"= "1.0"
                }
            }
            else {
                if (!$playbookResource.tags["hidden-SentinelTemplateName"]) {
                    Add-Member -InputObject $playbookResource.tags -Name "hidden-SentinelTemplateName" -Value $playbookResource.name -MemberType NoteProperty -Force
                }
                if (!$playbookResource.tags["hidden-SentinelTemplateVersion"]) {
                    Add-Member -InputObject $playbookResource.tags -Name "hidden-SentinelTemplateVersion" -Value "1.0" -MemberType NoteProperty -Force
                }
            }

            if ($playbookResource.identity.type -ne "SystemAssigned") {
                if (!$playbookResource.identity) {
                    Add-Member -InputObject $playbookResource -Name "identity" -Value @{
                        "type"= "SystemAssigned"
                    } -MemberType NoteProperty -Force
                }
                else {
                    $playbookResource.identity = @{
                        "type"= "SystemAssigned"
                    }
                }
            }
        }

        # Remove properties that are specific to an existing deployment and not needed for the template.
        $playbookResource.PSObject.Properties.remove("id")
        $playbookResource.location = "[resourceGroup().location]"
        $playbookResource.name = "[parameters('PlaybookName')]"
        Add-Member -InputObject $playbookResource -Name "apiVersion" -Value "2017-07-01" -MemberType NoteProperty
        Add-Member -InputObject $playbookResource -Name "dependsOn" -Value @() -MemberType NoteProperty

        $playbookResource.properties.PSObject.Properties.remove("createdTime")
        $playbookResource.properties.PSObject.Properties.remove("changedTime")
        $playbookResource.properties.PSObject.Properties.remove("version")
        $playbookResource.properties.PSObject.Properties.remove("accessEndpoint")
        $playbookResource.properties.PSObject.Properties.remove("endpointsConfiguration")

        if ($playbookResource.identity) {
            $playbookResource.identity.PSObject.Properties.remove("principalId")
            $playbookResource.identity.PSObject.Properties.remove("tenantId")
        }

        return $playbookResource
    }
    Catch {
        Write-Log -Message "Error occurred in GetPlaybookResource :$($_)" -Severity Error
    }
}

# Function to handle API connection references in the logic app definition,
# converting them to ARM template compatible resources and parameters.
Function HandlePlaybookApiConnectionReference($apiConnectionReference, $playbookResource) {
    Try {
        $connectionName = $apiConnectionReference.Name
        $connectionName = $connectionName.Split('_')[0].ToString().Trim()
        $connectionName = (Get-Culture).TextInfo.ToTitleCase($connectionName)

        if ($connectionName -ieq "azuresentinel") {
            $connectionVariableName = "MicrosoftSentinelConnectionName" 
            $templateVariables.Add($connectionVariableName, "[concat('MicrosoftSentinel-', parameters('PlaybookName'))]")           
        } else {
            $connectionVariableName = "$($connectionName)ConnectionName"
            $templateVariables.Add($connectionVariableName, "[concat('$connectionName-', parameters('PlaybookName'))]")
        }

        $connectorType = if ($apiConnectionReference.Value.id.ToLowerInvariant().Contains("/managedapis/")) { "managedApis" } else { "customApis" } 
        $connectionAuthenticationType = if ($apiConnectionReference.Value.connectionProperties.authentication.type -eq "ManagedServiceIdentity") { "Alternative" } else { $null }    

        # If generating for gallery and the connection is azuresentinel, convert to MSI if not already.
        if ($GenerateForGallery -and $connectionName -eq "azuresentinel" -and !$connectionAuthenticationType) {
            $connectionAuthenticationType = "Alternative"
            if (!$apiConnectionReference.Value.ConnectionProperties) {
                Add-Member -InputObject $apiConnectionReference.Value -Name "ConnectionProperties" -Value @{} -MemberType NoteProperty
            }
            $apiConnectionReference.Value.connectionProperties = @{
                "authentication"= @{
                    "type"= "ManagedServiceIdentity"
                }
            }
        }

        # Try to retrieve the existing connection and connector properties from ARM.
        try {
            $existingConnectionProperties = SendArmGetCall -relativeUrl "$($apiConnectionReference.Value.connectionId)?api-version=2016-06-01"
        }
        catch {
            $existingConnectionProperties = $null
        }

        $existingConnectorProperties = SendArmGetCall -relativeUrl "$($apiConnectionReference.Value.id)?api-version=2016-06-01"

        # Create the API connection resource entry for the ARM template.
        $apiConnectionResource = [ordered] @{
            "type"= "Microsoft.Web/connections"
            "apiVersion"= "2016-06-01"
            "name"= "[variables('$connectionVariableName')]"
            "location"= "[resourceGroup().location]"
            "kind"= "V1"
            "properties"= [ordered] @{
                "displayName"= "[variables('$connectionVariableName')]"
                "customParameterValues"= [ordered] @{}
                "parameterValueType"= $connectionAuthenticationType
                "api"= [ordered] @{
                    "id"= "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/$connectorType/$connectionName')]"
                }
            }
        }

        # If no parameterValueType needed, remove it.
        if (!$apiConnectionResource.properties.parameterValueType) {
            $apiConnectionResource.properties.Remove("parameterValueType")
        }

        # Add the constructed API connection resource to the list of resources.
        $apiConnectionResources.Add($apiConnectionResource) | Out-Null

        # Update the connection reference in the playbook resource to ARM template variables.
        $apiConnectionReference.Value = [ordered] @{
            "connectionId"= "[resourceId('Microsoft.Web/connections', variables('$connectionVariableName'))]"
            "connectionName" = "[variables('$connectionVariableName')]"
            "id" = "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/$connectorType/$connectionName')]"
            "connectionProperties" = $apiConnectionReference.Value.connectionProperties
        }

        # If no connectionProperties, remove the property from the reference.
        if (!$apiConnectionReference.Value.connectionProperties) {
            $apiConnectionReference.Value.Remove("connectionProperties")
        }

        # Add dependency on the newly created API connection resource.
        $playbookResource.dependsOn += "[resourceId('Microsoft.Web/connections', variables('$connectionVariableName'))]"
    }
    Catch {
        Write-Log -Message "Error occurred in HandlePlaybookApiConnectionReference :$($_)" -Severity Error
    }
}

# Function to build the final ARM template for the playbook,
# including parameters, variables, and resources.
Function BuildArmTemplate($playbookResource) {
    Try {
        $armTemplate = [ordered] @{
            '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
            "contentVersion"= "1.0.0.0"
            "parameters"= $PlaybookARMParameters
            "variables"= $templateVariables
            "resources"= @($playbookResource)+$apiConnectionResources
        }

        # If generating for the gallery, insert additional metadata.
        if ($GenerateForGallery) {
            $armTemplate.Insert(2, "metadata", [ordered] @{
                "title"= ""
                "description"= ""
                "prerequisites"= ""
                "postDeployment" = @()
                "prerequisitesDeployTemplateFile"= ""
                "lastUpdateTime"= ""
                "entities"= @()
                "tags"= @()
                "support"= [ordered] @{
                    "tier"= "community"
                    "armtemplate" = "Generated"
                }
                "author"= @{
                    "name"= ""
                }
            })
        }

        return $armTemplate
    }
    Catch {
        Write-Log -Message "Error occurred in BuildArmTemplate :$($_)" -Severity Error
    }
}

Write-Host "Exporting selected Logic Apps as ARM templates..."

# Export each selected Logic App as an ARM template.
foreach ($app in $selectedLogicApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name

    # Retrieve subscription, RG, and name for the ARM template build.
    $PlaybookSubscriptionId = $selectedSubscription.SubscriptionId
    $PlaybookResourceGroupName = $rg
    $PlaybookResourceName = $name

    # Clear parameters and resources for each new ARM template to avoid contamination.
    $PlaybookARMParameters.Clear()
    $templateVariables.Clear()
    $apiConnectionResources.Clear()

    # Get the playbook resource in a form suitable for ARM template export.
    $playbookResource = GetPlaybookResource
    if ($null -eq $playbookResource) {
        Write-Host "Could not build ARM template for '$name'. Skipping..." -ForegroundColor Yellow
        continue
    }

    # Check for API connections and handle them if present.
    $apiConnectionsReferences = $playbookResource.properties.definition?.resources?.actions | Where-Object { $_.value?.type -eq 'ApiConnection' }
    if ($apiConnectionsReferences) {
        foreach ($connRef in $apiConnectionsReferences) {
            HandlePlaybookApiConnectionReference -apiConnectionReference $connRef -playbookResource $playbookResource
        }
    }

    # Build the ARM template JSON.
    $armTemplate = BuildArmTemplate $playbookResource
    $armTemplateJson = ($armTemplate | ConvertTo-Json -Depth 50)
    $armTemplateJson = FixJsonIndentation $armTemplateJson

    # Export the ARM template to the chosen folder.
    $armFileName = Join-Path $exportFolder "$($name)_ARM.json"
    try {
        $armTemplateJson | Out-File -FilePath $armFileName -Encoding UTF8
        Write-Host "Exported ARM Template for '$name' to '$armFileName'"
    } catch {
        Write-Host "Failed to export ARM Template for '$name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Export complete. Check the 'Exports' folder for the ARM template files."
