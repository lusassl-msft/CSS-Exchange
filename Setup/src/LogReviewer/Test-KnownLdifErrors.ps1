Function Test-KnownLdifErrors {
    $schemaImportProcessFailure = Select-String "\[ERROR\] There was an error while running 'ldifde.exe' to import the schema file '(.*)'. The error code is: (\d+). More details can be found in the error file: '(.*)'" $SetupLog | Select-Object -Last 1

    if ($null -ne $schemaImportProcessFailure) {
        Write-ActionPlan("Failed to import schema setting from file '{0}'`r`n`tReview ldif.err file '{1}' to help determine which object in the file '{0}' was trying to be imported that was causing problems.`r`n`tIf you can't find the ldf file in the C:\Windows\Temp location, then find the file in the ISO." -f $schemaImportProcessFailure.Matches.Groups[1].Value,
            $schemaImportProcessFailure.Matches.Groups[3].Value)
        return $true
    }

    return $false
}