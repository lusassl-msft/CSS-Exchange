
Function Test-PrerequisiteCheck {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object]
        $SetupLogReviewer
    )

    begin {}
    process {

        if (($SetupLogReviewer.TestEvaluatedSettingOrRule("PendingRebootWindowsComponents", "Rule")) -eq "True") {
            Write-Output ("Computer is pending reboot based off the Windows Component is the registry") |
                Receive-Output -ForegroundColor Red
            return $true
        }

        $adValidationError = $SetupLogReviewer.SelectStringLastRunOfExchangeSetup("\[ERROR\] Setup encountered a problem while validating the state of Active Directory: (.*) See the Exchange setup log for more information on this error.")

        if ($adValidationError) {
            Write-Warning "Setup failed to validate AD environment level. This is the internal exception that occurred:"
            Write-Output($adValidationError.Matches.Groups[1].Value) |
                Receive-Output -ForegroundColor Yellow
            return $true
        }

        $schemaUpdateRequired = $SetupLogReviewer.SelectStringLastRunOfExchangeSetup("Schema Update Required Status : '(\w+)'.")
        $orgConfigUpdateRequired = $SetupLogReviewer.SelectStringLastRunOfExchangeSetup("Organization Configuration Update Required Status : '(\w+)'.")
        $domainConfigUpdateRequired = $SetupLogReviewer.SelectStringLastRunOfExchangeSetup("Domain Configuration Update Required Status : '(\w+)'.")

        if ($schemaUpdateRequired.Matches.Groups[1].Value -eq "True" -and
            ($SetupLogReviewer.TestEvaluatedSettingOrRule("SchemaAdmin")) -eq "False") {
            Write-Output ("/PrepareSchema is required and user $($SetupLogReviewer.User) isn't apart of the Schema Admins group.") |
                Receive-Output -ForegroundColor Red
            return $true
        }

        if ($schemaUpdateRequired.Matches.Groups[1].Value -eq "True" -and
            ($SetupLogReviewer.TestEvaluatedSettingOrRule("EnterpriseAdmin")) -eq "False") {
            Write-Output ("/PrepareSchema is required and user $($SetupLogReviewer.User) isn't apart of the Enterprise Admins group.") |
                Receive-Output -ForegroundColor Red
            return $true
        }

        if ($orgConfigUpdateRequired.Matches.Groups[1].Value -eq "True" -and
            ($SetupLogReviewer.TestEvaluatedSettingOrRule("EnterpriseAdmin")) -eq "False") {
            Write-Output ("/PrepareAD is required and user $($SetupLogReviewer.User) isn't apart of the Enterprise Admins group.") |
                Receive-Output -ForegroundColor Red
            return $true
        }

        if ($domainConfigUpdateRequired.Matches.Groups[1].Value -eq "True" -and
            ($SetupLogReviewer.TestEvaluatedSettingOrRule("EnterpriseAdmin")) -eq "False") {
            Write-Output ("/PrepareDomain needs to be run in this domain, but we actually require Enterprise Admin group to properly run this command.") |
                Receive-Output -ForegroundColor Red
            return $true
        }

        if (($SetupLogReviewer.TestEvaluatedSettingOrRule("ExOrgAdmin")) -eq "False") {
            $sid = $SetupLogReviewer.GetEvaluatedSettingOrRule("SidExOrgAdmins", "Setting", ".")
            if ($null -ne $sid) {
                Write-Output ("User $($SetupLogReviewer.User) isn't apart of Organization Management group.") |
                    Receive-Output -ForegroundColor Red
                Write-Output ("Looking to be in this group SID: $($sid.Matches.Groups[1].Value)")
                return $true
            } else {
                Write-Output ("Didn't find the user to be in ExOrgAdmin, but didn't find the SID for the group either. Suspect /PrepareAD hasn't been run yet.") |
                    Receive-Output -ForegroundColor Yellow
            }
        }
        return $false
    }
    end {}
}