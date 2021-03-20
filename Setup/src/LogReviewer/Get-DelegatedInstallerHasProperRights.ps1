# Get-DelegatedInstallerHasProperRights
#
# Identifies the issue described in https://support.microsoft.com/en-us/help/2961741
# by reading the setup log to see if this is why we failed.
#
# The article says this was fixed, but the fix was to add the Server Management
# group. The options are either add the delegated installer to that group, or
# remove them from whatever group is giving them too many rights (usually Domain Admins).
Function Get-DelegatedInstallerHasProperRights {

    if ((Test-EvaluatedSettingOrRule -SettingName "EnterpriseAdmin") -eq "True") {
        Write-Output "User that ran setup has EnterpriseAdmin and does not need to be in Server Management."
        return
    }

    if ((Test-EvaluatedSettingOrRule -SettingName "ExOrgAdmin") -eq "True") {
        Write-Output "User that ran setup has ExOrgAdmin and does not need to be in Server Management."
        return
    }

    if ((Test-EvaluatedSettingOrRule -SettingName "ServerAlreadyExists") -eq "False") {
        Write-Output "ServerAlreadyExists check came back False, and the user that ran setup does not have ExOrgAdmin or EnterpriseAdmin." -
        return
    }

    if ($null -eq (Test-EvaluatedSettingOrRule -SettingName "HasServerDelegatedPermsBlocked")) {
        Write-Output "HasServerDelegatedPermsBlocked returned no rights. This means the user that ran setup" `
            "does not have extra rights, and thus does not need to be in Server Management."
        return
    }

    $serverManagementValue = Test-EvaluatedSettingOrRule -SettingName "ServerManagement"

    if ($serverManagementValue -eq "True") {
        Write-Output "User that ran setup has extra rights to the server object, but is also a member of Server Management, so it's fine."
        return
    } elseif ($serverManagementValue -eq "False") {
        Write-Output "User that ran setup has extra rights to the server object and is not in Server Management. This causes setup to fail." |
            Receive-Output -ForegroundColor Red
        return
    }
}