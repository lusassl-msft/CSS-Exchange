# This script reviews the ExchangeSetup.log and determines if it is a known issue and reports an
# action to take to resolve the issue.
#
# Use the DelegateSetup switch if the log is from a Delegated Setup and you are running into a Prerequisite Check issue
#
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameter is used')]
[CmdletBinding(DefaultParameterSetName = "Main")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Main")]
    [System.IO.FileInfo]$SetupLog,
    [Parameter(ParameterSetName = "Main")]
    [switch]$DelegatedSetup,
    [Parameter(ParameterSetName = "PesterLoading")]
    [switch]$PesterLoad
)

$feedbackEmail = "ExToolsFeedback@microsoft.com"

Function Receive-Output {
    param(
        [string]$ForegroundColor
    )
    process { Write-Host $_ -ForegroundColor $ForegroundColor }
}

. $PSScriptRoot\LogReviewer\Get-DelegatedInstallerHasProperRights.ps1
. $PSScriptRoot\LogReviewer\New-SetupLogReviewer.ps1
. $PSScriptRoot\LogReviewer\Test-KnownOrganizationPreparationErrors.ps1
. $PSScriptRoot\LogReviewer\Test-KnownErrorReferenceSetupIssues.ps1
. $PSScriptRoot\LogReviewer\Test-OtherKnownIssues.ps1
. $PSScriptRoot\LogReviewer\Test-KnownLdifErrors.ps1
. $PSScriptRoot\LogReviewer\Test-PrerequisiteCheck.ps1

Function Get-EvaluatedSettingOrRule {
    param(
        [string]$SettingName,
        [string]$SettingOrRule = "Setting",
        [string]$ValueType = "\w"
    )
    return Select-String ("Evaluated \[{0}:{1}\].+\[Value:`"({2}+)`"\] \[ParentValue:" -f $SettingOrRule, $SettingName, $ValueType) $SetupLog | Select-Object -Last 1
}

Function Test-EvaluatedSettingOrRule {
    param(
        [string]$SettingName,
        [string]$SettingOrRule = "Setting"
    )
    $selectString = Get-EvaluatedSettingOrRule -SettingName $SettingName -SettingOrRule $SettingOrRule

    if ($null -ne $selectString -and
        (Test-LastRunOfExchangeSetup -TestingMatchInfo $selectString) -and
        $null -ne $selectString.Matches) {
        $selectStringValue = $selectString.Matches.Groups[1].Value

        if ($selectStringValue -ne "True" -and
            $selectStringValue -ne "False") {
            Write-Error ("{0} check has unexpected value: {1}" -f $SettingName, $selectStringValue)
            exit
        }
        return $selectStringValue
    }
    #Only need to handle this if the Evaluated setting might not occur all the time.
    return $null
}

Function Test-LastRunOfExchangeSetup {
    param(
        [object]$TestingMatchInfo
    )
    return $TestingMatchInfo.LineNumber -gt $Script:validSetupLog.LineNumber
}

Function Get-StringInLastRunOfExchangeSetup {
    param(
        [string]$SelectStringPattern
    )
    $selectStringResults = Select-String $SelectStringPattern $SetupLog | Select-Object -Last 1

    if ($null -ne $selectStringResults -and
        (Test-LastRunOfExchangeSetup -TestingMatchInfo $selectStringResults)) {
        return $selectStringResults
    }
    return $null
}

Function Write-ErrorContext {
    param(
        [array]$WriteInfo
    )
    Write-Warning ("Found Error: `r`n")
    foreach ($line in $WriteInfo) {
        Write-Output $line |
            Receive-Output -ForegroundColor Yellow
    }
}

Function Write-ActionPlan {
    param(
        [string]$ActionPlan
    )
    Write-Output("`r`nDo the following action plan:`r`n`t{0}" -f $ActionPlan) |
        Receive-Output -ForegroundColor Gray
    Write-Output("`r`nIf this doesn't resolve your issues, please let us know at {0}" -f $feedbackEmail)
}

Function Write-LogicalError {
    $display = "Logical Error has occurred. Please notify {0}" -f $feedbackEmail
    Write-Error $display
}

Function Get-FirstErrorWithContextToErrorReference {
    param(
        [int]$Before = 0,
        [int]$After = 200,
        [int]$ErrorReferenceLine
    )
    $allErrors = Select-String "\[ERROR\]" $SetupLog -Context $Before, $After
    $errorContext = New-Object 'System.Collections.Generic.List[string]'

    foreach ($currentError in $allErrors) {
        if (Test-LastRunOfExchangeSetup -TestingMatchInfo $currentError) {

            if ($Before -ne 0) {
                $currentError.Context.PreContext |
                    ForEach-Object {
                        $errorContext.Add($_)
                    }
            }

            $errorContext.Add($currentError.Line)
            $linesWant = $ErrorReferenceLine - $currentError.LineNumber
            $i = 0
            while ($i -lt $linesWant) {
                $errorContext.Add($currentError.Context.PostContext[$i])
                $i++
            }
            return $errorContext
        }
    }
}

Function Main {
    try {

        if ($PesterLoad) {
            return
        }

        if (-not ([IO.File]::Exists($SetupLog))) {
            Write-Error "Could not find file: $SetupLog"
            return
        }

        $setupLogReviewer = New-SetupLogReviewer -SetupLog $SetupLog -ErrorAction Stop
        $runDate = $setupLogReviewer.SetupRunDate
        $color = "Gray"

        if ($runDate -lt ([datetime]::Now.AddDays(-14))) { $color = "Yellow" }
        Write-Output "Setup.exe Run Date: $runDate" | Receive-Output -ForegroundColor $color

        if ($null -ne $setupLogReviewer.LocalBuildNumber) {
            Write-Output "Current Exchange Build: $($setupLogReviewer.LocalBuildNumber)"

            if ($setupLogReviewer.LocalBuildNumber -eq $setupLogReviewer.SetupBuildNumber) {
                Write-Output "Same build number detected..... if using powershell.exe to start setup. Make sure you do '.\setup.exe'" |
                    Receive-Output -ForegroundColor Red
            }
        }

        if ($DelegatedSetup) {
            Get-DelegatedInstallerHasProperRights
            return
        }

        if ($setupLogReviewer | Test-PrerequisiteCheck) {

            Write-Output "`r`nAdditional Context:"
            Write-Output ("User Logged On: $($setupLogReviewer.User)")

            $serverFQDN = Get-EvaluatedSettingOrRule -SettingName "ComputerNameDnsFullyQualified" -ValueType "."

            if ($null -ne $serverFQDN) {
                $serverFQDN = $serverFQDN.Matches.Groups[1].Value
                Write-Output "Setup Running on: $serverFQDN"
                $setupDomain = $serverFQDN.Split('.')[1]
                Write-Output "Setup Running in Domain: $setupDomain"
            }

            $siteName = Get-EvaluatedSettingOrRule -SettingName "SiteName" -ValueType "."

            if ($null -ne $siteName) {
                Write-Output "Setup Running in AD Site Name: $($siteName.Matches.Groups[1].Value)"
            }

            $schemaMaster = Get-StringInLastRunOfExchangeSetup -SelectStringPattern "Setup will attempt to use the Schema Master domain controller (.+)"

            if ($null -ne $schemaMaster) {
                Write-Output "----------------------------------"
                Write-Output "Schema Master: $($schemaMaster.Matches.Groups[1].Value)"
                $smDomain = $schemaMaster.Matches.Groups[1].Value.Split(".")[1]
                Write-Output "Schema Master in Domain: $smDomain"

                if ($smDomain -ne $setupDomain) {
                    Write-Output "Unable to run setup in current domain." |
                        Receive-Output -ForegroundColor "Red"
                }
            }

            return
        }

        if (Test-KnownLdifErrors) {
            return
        }

        if (Test-KnownOrganizationPreparationErrors) {
            return
        }

        if (Test-KnownErrorReferenceSetupIssues) {
            return
        }

        if (Test-OtherKnownIssues) {
            return
        }

        Write-Output "Looks like we weren't able to determine the cause of the issue with Setup. Please run SetupAssist.ps1 on the server." `
            "If that doesn't find the cause, please notify $feedbackEmail to help us improve the scripts."
    } catch {
        Write-Output "$($Error[0].Exception)"
        Write-Output "$($Error[0].ScriptStackTrace)"
        Write-Warning ("Ran into an issue with the script. If possible please email the Setup Log to {0}, or at least notify them of the issue." -f $feedbackEmail)
    }
}

Main