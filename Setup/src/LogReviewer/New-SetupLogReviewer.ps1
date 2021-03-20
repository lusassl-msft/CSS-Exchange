
Function New-SetupLogReviewer {
    [CmdletBinding()]
    param(
        [string]$SetupLog
    )
    begin {
        $validSetupLog = $null
        $currentLogOnUser = $null
        $exchangeBuildNumber = $null
        $localInstall = $null
    }
    process {
        $validSetupLog = Select-String "Starting Microsoft Exchange Server \d\d\d\d Setup" $SetupLog | Select-Object -Last 1

        if ($null -eq $validSetupLog) {
            throw "Failed to provide valid Exchange Setup Log"
        }

        $setupBuildNumber = Select-String "Setup version: (.+)\." $SetupLog | Select-Object -Last 1
        $runDate = [DateTime]::Parse(
            $SetupBuildNumber.Line.Substring(1,
                $SetupBuildNumber.Line.IndexOf("]") - 1)
        )
        $setupBuildNumber = $setupBuildNumber.Matches.Groups[1].Value
        $currentLogOnUser = Select-String "Logged on user: (.+)." $SetupLog | Select-Object -Last 1
    }
    end {
        $logReviewer = [PSCustomObject]@{
            SetupLog         = $SetupLog
            LastSetupRunLine = $validSetupLog.LineNumber
            User             = $currentLogOnUser.Matches.Groups[1].Value
            SetupRunDate     = $runDate
            LocalBuildNumber = $exchangeBuildNumber
            SetupBuildNumber = $setupBuildNumber
        }

        $logReviewer | Add-Member -MemberType ScriptMethod -Name "GetEvaluatedSettingOrRule" -Value {
            param(
                [string]$SettingName,
                [string]$SettingOrRule = "Setting",
                [string]$ValueType = "\w"
            )

            return Select-String ("Evaluated \[{0}:{1}\].+\[Value:`"({2}+)`"\] \[ParentValue:" -f $SettingOrRule, $SettingName, $ValueType) $this.SetupLog | Select-Object -Last 1
        }

        $logReviewer | Add-Member -MemberType ScriptMethod -Name "IsInLastRunOfExchangeSetup" -Value {
            param(
                [object]$TestingMatchInfo
            )
            return $TestingMatchInfo.LineNumber -gt $this.LastSetupRunLine
        }

        $logReviewer | Add-Member -MemberType ScriptMethod -Name "SelectStringLastRunOfExchangeSetup" -Value {
            param(
                [string]$SelectStringPattern
            )
            $selectStringResults = Select-String $SelectStringPattern $this.SetupLog | Select-Object -Last 1
        
            if ($null -ne $selectStringResults -and
                ($this.IsInLastRunOfExchangeSetup($selectStringResults))) {
                return $selectStringResults
            }
            return $null
        }

        $logReviewer | Add-Member -MemberType ScriptMethod -Name "TestEvaluatedSettingOrRule" -Value {
            param(
                [string]$SettingName,
                [string]$SettingOrRule = "Setting"
            )

            $selectString = $this.GetEvaluatedSettingOrRule($SettingName, $SettingOrRule)

            if ($null -ne $selectString -and
                ($this.IsInLastRunOfExchangeSetup($selectString)) -and
                $null -ne $selectString.Matches) {
                $selectStringValue = $selectString.Matches.Groups[1].Value

                if ($selectStringValue -ne "True" -and
                    $selectStringValue -ne "False") {
                    throw "$SettingName check has unexpected value: $selectStringValue"
                }

                return $selectStringValue
            }
            return $null
        }

        $localInstall = $logReviewer.SelectStringLastRunOfExchangeSetup("The locally installed version is (.+)\.")
        if ($null -ne $localInstall) {
            $logReviewer.LocalBuildNumber = $localInstall.Matches.Groups[1].Value
        }

        return $logReviewer
    }
}
