# Load dependencies
. "$PSScriptRoot/Find-ConfigFile.ps1"
. "$PSScriptRoot/Write-Log.ps1"

# ===================================================================
# HARDCODED FOR DEBUGGING - START
# ===================================================================
# $PROD_DATABASE="nextXdb"  # Commented out - using .env value instead
# ===================================================================
# HARDCODED FOR DEBUGGING - END
# ===================================================================

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

Write-Log "DEBUG: PowerShell PROD_DATABASE: '$PROD_DATABASE', Environment PROD_DATABASE: '$env:PROD_DATABASE'"

$global:LogDatabaseName = $PROD_DATABASE

# ---------- Generate File Names and Folders ----------
$dbBackupFolder = Join-Path -Path $BACKUP_FOLDER -ChildPath $PROD_DATABASE
if (-not (Test-Path -Path $dbBackupFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $dbBackupFolder -Force | Out-Null
}

$Timestamp  = Get-Date -Format "yyyyMMdd_HHmm"
$global:SchemaDacpacFile = Join-Path -Path $dbBackupFolder -ChildPath "$($PROD_DATABASE)_SchemaOnly_$Timestamp.dacpac"
$global:TempDataFolder = Join-Path -Path $dbBackupFolder -ChildPath "TempData_$Timestamp"

# Ensure the TempDataFolder exists for the BCP files
if (-not (Test-Path -Path $global:TempDataFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $global:TempDataFolder -Force | Out-Null
}
Set-Content -Path (Join-Path -Path $dbBackupFolder -ChildPath "last_temp_folder.txt") -Value $global:TempDataFolder

# ---------- Load Masking Configuration ----------
$maskingConfigFile = Find-ConfigFile -fileName "$($PROD_DATABASE)_config.json"
if (-not $maskingConfigFile) {
    Write-Log "WARNING: masking-config.json not found. Cannot export selective table data." "WARN"
    $maskingConfig = @{} # Empty config to avoid errors
} else {
    $maskingConfig = Get-Content $maskingConfigFile | ConvertFrom-Json
}

# ---------- Verify Production Database Exists ----------
Write-Log "Verifying production database [$PROD_DATABASE] on [$PROD_SERVER] exists..."
$checkProdDbCmd = "IF DB_ID('$PROD_DATABASE') IS NULL SELECT 'NOT_EXISTS' ELSE SELECT 'EXISTS';"
try {
    $LASTEXITCODE = 0 # Reset exit code
    $prodDbExists = sqlcmd -S $PROD_SERVER -U $PROD_USER -P $PROD_PASSWORD -Q $checkProdDbCmd -h -1 | Where-Object { $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() }

    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: sqlcmd failed to check production DB existence with exit code $LASTEXITCODE. Please check server name, credentials, and network connectivity." "ERROR"
        exit 1
    }

    if ($prodDbExists -eq "NOT_EXISTS") {
        Write-Log "ERROR: Production database [$PROD_DATABASE] not found on server [$PROD_SERVER]. Exiting." "ERROR"
        exit 1
    }
    Write-Log "Production database [$PROD_DATABASE] found."
} catch {
    Write-Log "ERROR: Failed to verify production database existence - $_. Please check server name, credentials, and network connectivity." "ERROR"
    exit 1
}

# ---------- Step 1.1: Extract Schema-Only DACPAC from Production ----------
Write-Log "Step 1.1: Extracting Schema-Only DACPAC [$PROD_DATABASE] from Server [$PROD_SERVER]"
Write-Log "Schema DACPAC file will be: $SchemaDacpacFile"
try {
    $LASTEXITCODE = 0 # Reset exit code
    & "$SQLPACKAGE_PATH" /Action:Extract `
        /SourceServerName:$PROD_SERVER `
        /SourceDatabaseName:$PROD_DATABASE `
        /TargetFile:$SchemaDacpacFile `
        /p:ExtractAllTableData=False `
        /SourceTrustServerCertificate:True `
        /SourceUser:$PROD_USER `
        /SourcePassword:$PROD_PASSWORD # This parameter is for DACPAC extract to exclude data

    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: SqlPackage.exe DACPAC extraction failed with exit code $LASTEXITCODE." "ERROR"
        exit 1
    }

    if (Test-Path $SchemaDacpacFile) {
        Write-Log "Schema-Only DACPAC extraction completed successfully: $SchemaDacpacFile"
        Write-Log "Verification: Schema DACPAC file exists at $SchemaDacpacFile"
    } else {
        Write-Log "ERROR: Verification: Schema DACPAC file NOT FOUND at $SchemaDacpacFile after extraction." "ERROR"
        exit 1
    }
} catch {
    Write-Log "ERROR: Schema-Only DACPAC extraction failed - $_" "ERROR"
    exit 1
}

# ---------- Step 1.2: Export Data for Selected Tables using BCP ----------
if (($maskingConfig.PSObject.Properties.Name -contains 'tablesToExcludeData') -or ($maskingConfig.PSObject.Properties.Name -contains 'tablesToRestoreData')) { # Check if either exclusion or inclusion is defined
    Write-Log "Step 1.2: Exporting data for selected tables using BCP."
    if (!(Test-Path $TempDataFolder)) {
        New-Item -ItemType Directory -Path $TempDataFolder | Out-Null
    }

    # Get all user tables from the production database
    $allProdTablesQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_CATALOG = '$PROD_DATABASE' AND TABLE_SCHEMA = 'dbo';"
    try {
        $allProdTables = sqlcmd -S $PROD_SERVER -U $PROD_USER -P $PROD_PASSWORD -d $PROD_DATABASE -Q $allProdTablesQuery -h -1 | Where-Object { $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) }
    } catch {
        Write-Log "ERROR: Could not retrieve all table names from production database. - $_" "ERROR"
        exit 1
    }

    $tablesToExportData = @()
    if ($maskingConfig.tablesToRestoreData -and $maskingConfig.tablesToRestoreData.Count -gt 0) { # Whitelist approach
        $tablesToExportData = $allProdTables | Where-Object { $_ -in $maskingConfig.tablesToRestoreData }
        Write-Log "Using whitelist approach. Tables to export data: $($tablesToExportData -join ', ')"
    } elseif ($maskingConfig.PSObject.Properties.Name -contains 'tablesToExcludeData') { # Blacklist approach
        $tablesToExportData = $allProdTables | Where-Object { $_ -notin $maskingConfig.tablesToExcludeData }
        Write-Log "Using blacklist approach. Tables to export data: $($tablesToExportData -join ', ')"
    } else {
        Write-Log "No tables specified for data export (neither whitelist nor blacklist). Skipping data export." "INFO"
    }

    foreach ($tableName in $tablesToExportData) {
        $dataFile = "$TempDataFolder/$tableName.csv"
        Write-Log "Exporting data for table '$tableName' to '$dataFile'..."
        try {
            $LASTEXITCODE = 0 # Reset exit code
            # bcp command: [database].[schema].[table] out [datafile] -c -t, -S [server] -U [user] -P [password]
            & bcp "$PROD_DATABASE.dbo.$tableName" out "$dataFile" -n -S "$PROD_SERVER" -U "$PROD_USER" -P "$PROD_PASSWORD"

            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: BCP data export for table '$tableName' failed with exit code $LASTEXITCODE." "ERROR"
                exit 1
            }
            Write-Log "Data export for table '$tableName' completed successfully."
        } catch {
            Write-Log "ERROR: BCP data export for table '$tableName' failed - $_" "ERROR"
            exit 1
        }
    }
    Write-Log "Data export for all selected tables completed successfully to $TempDataFolder."
} else {
    Write-Log "No tables specified for data export (neither whitelist nor blacklist). Skipping data export." "INFO"
}

Write-Log "Export process completed successfully."