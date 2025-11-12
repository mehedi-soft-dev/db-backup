# Load dependencies
. "$PSScriptRoot/Find-ConfigFile.ps1"
. "$PSScriptRoot/Write-Log.ps1"

# ---------- Load Environment Variables ----------
$envFile = Find-ConfigFile -fileName ".env"
if (-not $envFile) {
    Write-Log "ERROR: .env file not found."
    exit 1
}
$envVars = Get-Content $envFile | Where-Object { $_ -match "^[^#].+=" }
foreach ($line in $envVars) {
    $parts = $line -split '=',2
    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim("'`"")  # remove quotes
    Set-Variable -Name $name -Value $value -Scope Global
}

# Set the database context for the logger
$global:LogDatabaseName = $PROD_DATABASE

# ---------- Step 5: Clear Temporary Files ----------
Write-Log "Step 5: Checking for temporary data files to clear."

$prodBackupFolder = Join-Path -Path $BACKUP_FOLDER -ChildPath $PROD_DATABASE
$lastTempFile = Join-Path -Path $prodBackupFolder -ChildPath "last_temp_folder.txt"

if (Test-Path $lastTempFile) {
    $tempDataFolder = Get-Content $lastTempFile -ErrorAction SilentlyContinue
    if ($tempDataFolder -and (Test-Path $tempDataFolder)) {
        try {
            Remove-Item -Path $tempDataFolder -Recurse -Force
            Write-Log "Temporary data folder '$tempDataFolder' cleared successfully."
        } catch {
            Write-Log "ERROR: Failed to clear temporary data folder '$tempDataFolder' - $_" "ERROR"
        }
    } else {
        Write-Log "Temporary data folder path found, but folder '$tempDataFolder' does not exist. Nothing to clear." "INFO"
    }
    # Clean up the pointer file itself
    try {
        Remove-Item -Path $lastTempFile -Force
        Write-Log "Pointer file '$lastTempFile' cleared successfully."
    } catch {
        Write-Log "ERROR: Failed to clear pointer file '$lastTempFile' - $_" "ERROR"
    }
} else {
    Write-Log "Pointer file '$lastTempFile' not found. Nothing to clear." "INFO"
}
