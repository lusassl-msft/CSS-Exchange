Function Test-KnownErrorReferenceSetupIssues {

    $errorReference = Select-String "\[ERROR-REFERENCE\] Id=(.+) Component=" $SetupLog | Select-Object -Last 1

    if ($null -eq $errorReference -or
        !(Test-LastRunOfExchangeSetup -TestingMatchInfo $errorReference)) {
        return $false
    }

    $allErrors = Select-String "\[ERROR\]" $SetupLog -Context 0, 200
    $errorContext = @()

    foreach ($currentError in $allErrors) {
        if (Test-LastRunOfExchangeSetup -TestingMatchInfo $currentError) {
            #from known cases, this should be rather small
            $linesWant = $errorReference.LineNumber - $currentError.LineNumber
            $i = 0
            while ($i -lt $linesWant) {
                $errorContext += $currentError.Context.PostContext[$i++]
            }
            break
        }
    }

    $invalidWKObjectTargetException = $errorContext | Select-String `
        -Pattern "The well-known object entry with the GUID `"(.+)`", which is on the `"(.+)`" container object's otherWellKnownObjects attribute, refers to a group `"(.+)`" of the wrong group type. Either delete the well-known object entry, or promote the target object to `"(.+)`"." `
    | Select-Object -Last 1

    if ($null -ne $invalidWKObjectTargetException) {
        Write-ErrorContext -WriteInfo $invalidWKObjectTargetException.Line
        $ap = "- Change the {0} object to {1}" -f $invalidWKObjectTargetException.Matches.Groups[3].Value,
        $invalidWKObjectTargetException.Matches.Groups[4].Value
        $ap += "`r`n`t- Another problem can be that the group is set correctly, but is mail enabled and shouldn't be."
        Write-ActionPlan ($ap)

        return $true
    }

    $msExchangeSecurityGroupsContainerDeleted = $errorContext | Select-String `
        -Pattern "System.NullReferenceException: Object reference not set to an instance of an object.", `
        "Microsoft.Exchange.Management.Tasks.InitializeExchangeUniversalGroups.CreateOrMoveEWPGroup\(ADGroup ewp, ADOrganizationalUnit usgContainer\)"

    if ($null -ne $msExchangeSecurityGroupsContainerDeleted) {
        if ($msExchangeSecurityGroupsContainerDeleted[0].Pattern -ne $msExchangeSecurityGroupsContainerDeleted[1].Pattern -and
            $msExchangeSecurityGroupsContainerDeleted[0].LineNumber -eq ($msExchangeSecurityGroupsContainerDeleted[1].LineNumber - 1)) {
            Write-ErrorContext -WriteInfo @($msExchangeSecurityGroupsContainerDeleted[0].Line,
                $msExchangeSecurityGroupsContainerDeleted[1].Line)
            Write-ActionPlan("'OU=Microsoft Exchange Security Groups' was deleted from the root of the domain. We need to have it created again at the root of the domain to continue.")
            return $true
        }
    }

    $exceptionADOperationFailedAlreadyExist = $errorContext | Select-String `
        -Pattern "Active Directory operation failed on (.+). The object '(.+)' already exists." `
    | Select-Object -First 1

    if ($null -ne $exceptionADOperationFailedAlreadyExist) {
        Write-ErrorContext -WriteInfo $exceptionADOperationFailedAlreadyExist.Line
        Write-ActionPlan("Validate permissions are inherited to object `"{0}`" and that there aren't any denies that shouldn't be there" -f $exceptionADOperationFailedAlreadyExist.Matches.Groups[2])
        return $true
    }

    return $false
}
