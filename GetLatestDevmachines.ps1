<#
	- Requires -RunAsAdministrator, when ran from PowerShell.
	- The Power Shell cmdlets and Windows Shell Extension (x64) needs to be installed 
	from the Team Foundation Server Power tools package for TFS get latest.
	- To enable power shell script execution in AX 7.2 and up machines:
	Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
#>

# Link modules
Add-PSSnapin Microsoft.TeamFoundation.PowerShell

# Find the correct Package Local Directory (PLD)
$pldPath = "\AOSService\PackagesLocalDirectory"
$packageDirectory = "{0}:$pldPath" -f ('J','K')[$(Test-Path $("K:$pldPath"))]  
$scriptPath = "{0}\Plugins\AxReportVmRoleStartupTask" -f $packageDirectory

Import-Module "$scriptPath\AosCommon.psm1" -force -DisableNameChecking
Import-Module "$scriptPath\CommonRollbackUtilities.psm1" -force -DisableNameChecking

function Log-Message
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$LogMessage
    )

    Write-Output ("{0} - {1}" -f (Get-Date), $LogMessage)
}

function Get-Latest()
{
    try
    {
		$logFile = "{0}\Logs\GetLatestLog.txt" -f $PSScriptRoot

	    # Get the latest version of the code for the worspace
	    Update-TfsWorkSpace -Item $packageDirectory -Overwrite -Recurse -Version T >> $logFile

		$logFile
    }
    catch
    {
        $message = '@channel {0} get latest failed' -f $env:COMPUTERNAME
        $TeamMessage = '@general {0} get latest failed' -f $env:COMPUTERNAME

        PostToMSTeam -Message $TeamMessage
         
        
        throw 'Exception occured when getting latest checkins from source control'
    }
}

function Build-Model($modelName)
{
    try
    {
	    #Rebuild selected model
	    $logMessage = "Rebuild model {0} start" -f $modelName	
	    Log-Message $logMessage

		$logFile = "{0}\Logs\{1}BuildLog.txt" -f $PSScriptRoot, $modelName

	    # Set executable
 	    $modelExecutable = '{0}\bin\xppc.exe' -f $packageDirectory

	    $params = @(
		        '-metadata="{0}"' -f $packageDirectory
		        '-compilermetadata="{0}"' -f $packageDirectory
		        '-xref'
		        '-xrefSqlServer="localhost"'
		        '-xrefDbName="DYNAMICSXREFDB"'
		        '-output="{0}\{1}\bin"' -f $packageDirectory,$modelName
		        '-modelmodule="{0}"' -f $modelName
		        '-xmllog="{0}\Logs\{1}BuildModelResult.xml"' -f $PSScriptRoot,$modelName
		        '-log="{0}\Logs\{1}BuildModelResult.log"' -f $PSScriptRoot,$modelName
		        '-appBase="{0}\bin"' -f $packageDirectory
		        '-refPath="{0}\{1}\bin"' -f $packageDirectory,$modelName
		        '-referenceFolder="{0}"' -f $packageDirectory
		       )

	    # Execute build
	    & $modelExecutable $params 2>&1 >> $logFile

		$logFile

	    $logMessage = "Rebuild model {0} end" -f $modelName	
	    Log-Message $logMessage
    }
    catch
    {
       
        $TeamMessage = '@general {0} model {1} build failed' -f $env:COMPUTERNAME, $modelsToBuild[$i]

        PostToMSTeam -Message $TeamMessage
                
        throw 'Exception occured when building application suite'
    }
}

function Build-Models
{
    $modelsFile = "{0}\BuildModels.txt" -f $PSScriptRoot
    $modelsToBuild = Get-Content $modelsFile
    
    for ($i=0; $i -lt $modelsToBuild.count; $i++)
    {
        if ($modelsToBuild[$i] -inotin '')
        {
            Build-Model $modelsToBuild[$i]

            $resultLOGTarget = "{0}\Logs\{1}BuildModelResult.log" -f $PSScriptRoot, $modelsToBuild[$i]
            
            $hasErrors = Get-Content $resultLOGTarget | Select-String -Pattern 'Errors: '

            if ($hasErrors[0] -inotin 'Errors: 0')
            {
                $message = '@channel {0} model {1} build failed with {2}' -f $env:COMPUTERNAME, $modelsToBuild[$i], $hasErrors
                $message = '@general {0} model {1} build failed with {2}' -f $env:COMPUTERNAME, $modelsToBuild[$i], $hasErrors

                PostToMSTeam -Message $TeamMessage
                
                Exit
            }
        }
    }
}

function Run-DBSync()
{
	try
    {
		$logFile = "{0}\Logs\SyncDBLog.txt" -f $PSScriptRoot

        # Set the executable 
 	    $SyncToolExecutable = '{0}\bin\SyncEngine.exe' -f $packageDirectory

	    # Set connection string     
	    $connectionString = "Data Source=localhost; " +
		                "Integrated Security=True; " +
		                "Initial Catalog=AxDb"
 
	    # Set parameters
	    $params = @(
		        "-syncmode=`"fullall`""
	                "-metadatabinaries=$packageDirectory"
	                "-connect=`"$connectionString`""
		       )

	    # Execute syncronization 
	    & $SyncToolExecutable $params 2>&1 >> $logFile

		$logFile
    } 
    catch
    {
        $TeamMessage = '@general {0} DB synchronization failed' -f $env:COMPUTERNAME

        PostToMSTeam -Message $TeamMessage
                
        throw 'Exception occurred when synchronizing DB'
    }
}

function Run-RepPublish()
{
    try
    {
		$logFile = "{0}\Logs\DeployReportsLog.txt" -f $PSScriptRoot

	    #Publish SSRS Reports
	    Set-ExecutionPolicy Unrestricted
	    & $scriptPath\DeployAllReportsToSSRS.ps1 -PackageInstallLocation "$packageDirectory" >> $logFile

		$logFile
    }
    catch
    {
        
        $TeamMessage = '@general {0} report deployment failed' -f $env:COMPUTERNAME

        PostToMSTeam -Message $TeamMessage
             

        throw 'Exception occured when deploying report'
    }
}

function resetiis
{
    try
    {
        invoke-command -scriptblock {iisreset}
    }
    catch
    {
        $TeamMessage = '@general {0} iisreset failed' -f $env:COMPUTERNAME

        PostToMSTeam -Message $TeamMessage
        
        throw 'Exception when restting iis' 
    }
}

function PostToSlack 
{
    Param(
        [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Slack channel')]
        [ValidateNotNullorEmpty()]
        [String]$Channel,
        [Parameter(Mandatory = $true,Position = 1,HelpMessage = 'Chat message')]
        [ValidateNotNullorEmpty()]
        [String]$Message,
        [Parameter(Mandatory = $false,Position = 2,HelpMessage = 'Slack API token')]
        [ValidateNotNullorEmpty()]
        [String]$token,
        [Parameter(Mandatory = $false,Position = 3,HelpMessage = 'Optional name for the bot')]
        [String]$BotName = 'PowerShell Bot'
    )

    Process {

        # Static parameters
        if (!$token) 
        {
            $tokenFile = "{0}\slackToken.txt" -f $PSScriptRoot
            $token = Get-Content $tokenFile
        }

        $uri = 'https://slack.com/api/chat.postMessage'
        
        $body = @{
            token    = $token
            channel  = $Channel
            text     = $Message
            username = $BotName
            parse    = 'full'
        }

        # Call the API
        try 
        {
            Invoke-RestMethod -Uri $uri -Body $body
        }
        catch 
        {
            throw 'Unable to call the API'
        }

    } 
}#>

function PostToMSTeam 
{
    Param(        
        [Parameter(Mandatory = $true,Position = 0,HelpMessage = 'Chat message')]
        [ValidateNotNullorEmpty()]
        [String]$Message        
        )

    Process 
    {                
        $MSTeamUri   = 'https://outlook.office.com/webhook/7cb76930-ad2c-43b1-8d5e-35119c37719d@c8f08d7a-5d31-4558-b0ca-b619c9a3d60a/IncomingWebhook/66535ec6318049bcbd37aa48d8a75772/80990c87-0e6c-40c0-8139-5dd0cf1e1aa9'   
        $messageBody = ConvertTo-JSON @{text = $Message}   

        # Call the API
        try 
        {            
            Invoke-RestMethod -uri $MSTeamUri -Method Post -body $messageBody -ContentType 'application/json'
        }
        catch 
        {
            throw 'Unable to call the MSTeam API'
        }

    } 
}#>

# Call the TFS get latest functionality
#Log-Message "Get latest start"
Get-Latest
Log-Message "Get latest end"

# Call model build functinalty (there is no switch for rebuilding all models at once, so build needs to be called for each model requiring rebuild
Log-Message "Build models start"
Build-Models
Log-Message "Build models end"

# Call the DB syncronization functionality
Log-Message "DB Synchronization start"
Run-DBSync
Log-Message "DB Synchronization end"

# Call the SSRS reports deployment functionality
Log-Message "Reports deployment start"
Run-RepPublish
Log-Message "Reports deployment end"

#IIS reset
resetiis
