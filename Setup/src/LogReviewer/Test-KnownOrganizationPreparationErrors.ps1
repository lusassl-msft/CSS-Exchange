Function Test-KnownOrganizationPreparationErrors {

    $errorReference = Select-String "\[ERROR-REFERENCE\] Id=(.+) Component=" $SetupLog | Select-Object -Last 1

    if ($null -eq $errorReference -or
        !(Test-LastRunOfExchangeSetup -TestingMatchInfo $errorReference)) {
        return $false
    }

    $errorLine = Select-String "\[ERROR\] The well-known object entry (.+) on the otherWellKnownObjects attribute in the container object (.+) points to an invalid DN or a deleted object" $SetupLog | Select-Object -Last 1

    if ($null -ne $errorLine -and
        (Test-LastRunOfExchangeSetup -TestingMatchInfo $errorLine)) {

        Write-ErrorContext -WriteInfo $errorLine.Line
        [string]$ap = "Option 1: Restore the objects that were deleted."
        [string]$ap += "`r`n`tOption 2: Run the SetupAssist.ps1 script with '-OtherWellKnownObjects' to be able address deleted objects type"
        Write-ActionPlan $ap
        return $true
    }

    #_27a706ffe123425f9ee60cb02b930e81 initialize permissions of the domain.
    if ($errorReference.Matches.Groups[1].Value -eq "DomainGlobalConfig___27a706ffe123425f9ee60cb02b930e81") {
        $errorContext = Get-FirstErrorWithContextToErrorReference -Before 1 -ErrorReferenceLine $errorReference.LineNumber
        $permissionsError = $errorContext | Select-String "SecErr: DSID-03152857, problem 4003 \(INSUFF_ACCESS_RIGHTS\)"

        if ($null -ne $permissionsError) {
            $objectDN = $errorContext[0] | Select-String "Used domain controller (.+) to read object (.+)."

            if ($null -ne $objectDN) {
                Write-ErrorContext -WriteInfo ($errorContext | Select-Object -First 10)
                [string]$ap = "We failed to have the correct permissions to write ACE to '$($objectDN.Matches.Groups[2].Value)' as the current user $Script:currentLogOnUser"
                [string]$ap += "`r`n`t- Make sure there are no denies for this user on the object"
                [string]$ap += "`r`n`t- By default Enterprise Admins and BUILTIN\Administrators give you the rights to do this action (dsacls 'write permissions')"
                [string]$ap += "`r`n`t- If unable to determine the cause, you can apply FULL CONTROL to '$($objectDN.Matches.Groups[2].Value)' for the user $Script:currentLogOnUser"
                Write-ActionPlan $ap
                return $true
            }
        }
    }
}