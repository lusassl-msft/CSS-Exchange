Function Test-OtherKnownIssues {

    if ((Test-EvaluatedSettingOrRule -SettingName "DidOnPremisesSettingCreatedAnException" -SettingOrRule "Rule") -eq "True") {
        $isHybridObjectFoundOnPremises = Select-String "Evaluated \[Setting:IsHybridObjectFoundOnPremises\]" $SetupLog -Context 20, 20 | Select-Object -Last 1

        if ($null -eq $isHybridObjectFoundOnPremises -or
            !(Test-LastRunOfExchangeSetup -TestingMatchInfo $isHybridObjectFoundOnPremises)) {
            Write-LogicalError
            return $true
        }

        $errorContext = @()

        foreach ($line in $isHybridObjectFoundOnPremises.Context.PreContext) {
            $errorContext += $line
        }

        foreach ($line in $isHybridObjectFoundOnPremises.Context.PostContext) {
            $errorContext += $line
        }

        $targetApplicationUri = $errorContext | Select-String `
            "Searching for (.+) as the TargetApplicationUri"

        if ($null -eq $targetApplicationUri -or
            $targetApplicationUri.Count -gt 1) {
            Write-LogicalError
            return $true
        }

        Write-ErrorContext -WriteInfo $errorContext
        Write-ActionPlan("One of the Organization Relationship objects has a null value to the ApplicationURI attribute. `r`n`tPlease add `"{0}`" to it" -f $targetApplicationUri.Matches.Groups[1].Value)
        return $true
    }

    return $false
}
