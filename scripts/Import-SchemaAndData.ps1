# Load dependencies
. "$PSScriptRoot/Find-ConfigFile.ps1"
. "$PSScriptRoot/Write-Log.ps1"

# ===================================================================
# HARDCODED FOR DEBUGGING - START
# ===================================================================
# $PROD_DATABASE="nextXdb"  # Commented out - using .env value instead
# $DEV_DATABASE="nextXdb_dev"  # Commented out - using .env value instead
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

$global:LogDatabaseName = $DEV_DATABASE

# ---------- Path and Configuration Setup ----------
$prodBackupFolder = (Resolve-Path (Join-Path -Path $BACKUP_FOLDER -ChildPath $PROD_DATABASE)).Path
$devBackupFolder = Join-Path -Path $BACKUP_FOLDER -ChildPath $DEV_DATABASE
if (-not (Test-Path -Path $devBackupFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $devBackupFolder -Force | Out-Null
}
$devBackupFolder = (Resolve-Path $devBackupFolder).Path

$maskingConfigFile = Find-ConfigFile -fileName "$($PROD_DATABASE)_config.json"
if (-not $maskingConfigFile) {
    Write-Log "WARNING: masking-config.json not found. Cannot import selective table data." "WARN"
    $maskingConfig = @{} # Empty config to avoid errors
} else {
    $maskingConfig = Get-Content $maskingConfigFile | ConvertFrom-Json
}

$lastTempFile = Join-Path -Path $prodBackupFolder -ChildPath "last_temp_folder.txt"
$global:TempDataFolder = Get-Content $lastTempFile -ErrorAction SilentlyContinue


# ---------- Ensure Backup Folder ----------

if (!(Test-Path $BACKUP_FOLDER)) {

    Write-Log "Backup folder does not exist. Creating..."

    New-Item -ItemType Directory -Path $BACKUP_FOLDER | Out-Null

}



# ---------- Step 2: Prepare Development Database (copied from Prepare-DevDB.ps1) ----------

Write-Log "Step 2: Prepare Development Database [$DEV_DATABASE] on [$DEV_SERVER]"



$checkCmd = "IF DB_ID('$DEV_DATABASE') IS NULL SELECT 'NOT_EXISTS' ELSE SELECT 'EXISTS';"

try {
    $LASTEXITCODE = 0 # Reset exit code
    $result = sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -Q $checkCmd -h -1 | Where-Object { $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() }

    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: sqlcmd failed to check Dev DB existence with exit code $LASTEXITCODE." "ERROR"
        exit 1
    }
} catch {
    Write-Log "ERROR: Cannot connect to Dev Server or check DB existence - $_" "ERROR"
    exit 1
}



if ($result -match "EXISTS") {

    Write-Log "Dev DB exists. Backing up before dropping..."

    $TimestampDevBackup  = Get-Date -Format "yyyyMMdd_HHmm"

    $DevBackupFile = Join-Path -Path $devBackupFolder -ChildPath "$($DEV_DATABASE)_$TimestampDevBackup.bak"

    Write-Log "Backup file will be: $DevBackupFile"

    try {
        $LASTEXITCODE = 0 # Reset exit code
        sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -Q "BACKUP DATABASE [$DEV_DATABASE] TO DISK = '$DevBackupFile' WITH FORMAT, MEDIANAME = 'SQLServerBackups', NAME = 'Full Backup of $DEV_DATABASE';"

        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Dev DB backup failed with exit code $LASTEXITCODE." "ERROR"
            # Do not exit here, as the user might want to proceed with dropping/creating
        } else {
            Write-Log "Dev DB backup completed successfully."
        }
    } catch {
        Write-Log "ERROR: Cannot backup Dev DB - $_" "ERROR"
        # Do not exit here, as the user might want to proceed with dropping/creating
    }



    Write-Log "Dropping and recreating dev database..."

    try {
        $LASTEXITCODE = 0 # Reset exit code
        $recreateCmd = "
            ALTER DATABASE [$DEV_DATABASE] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
            DROP DATABASE [$DEV_DATABASE];
            CREATE DATABASE [$DEV_DATABASE];"
        sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -Q $recreateCmd

        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Failed to drop/recreate Dev DB with exit code $LASTEXITCODE." "ERROR"
            exit 1
        }
        Write-Log "Dev DB [$DEV_DATABASE] recreated successfully."
    } catch {
        Write-Log "ERROR: Cannot drop/create Dev DB - $_" "ERROR"
        exit 1
    }

} else {

    Write-Log "Dev DB does not exist. Creating..."

    try {
        $LASTEXITCODE = 0 # Reset exit code
        sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -Q "CREATE DATABASE [$DEV_DATABASE]"

        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Failed to create Dev DB with exit code $LASTEXITCODE." "ERROR"
            exit 1
        }
        Write-Log "Dev DB [$DEV_DATABASE] created successfully."
    } catch {
        Write-Log "ERROR: Cannot create Dev DB - $_" "ERROR"
        exit 1
    }

}



# ---------- Step 3.1: Publish Schema-Only DACPAC to Development ----------

Write-Log "Step 3.1: Publishing Schema-Only DACPAC to Development Database [$DEV_DATABASE]"



# Drop existing users from the database to prevent import errors

Write-Log "Dropping users from dev database..."

try {
    $LASTEXITCODE = 0 # Reset exit code
    $dropUserCmd = "
        DECLARE @user NVARCHAR(MAX);
        DECLARE user_cursor CURSOR FOR
        SELECT name FROM sys.database_principals WHERE type_desc = 'SQL_USER' AND name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys');
        OPEN user_cursor;
        FETCH NEXT FROM user_cursor INTO @user;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC('DROP USER [' + @user + ']');
            FETCH NEXT FROM user_cursor INTO @user;
        END;
        CLOSE user_cursor;
        DEALLOCATE user_cursor;"
    sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -d $DEV_DATABASE -Q $dropUserCmd

    if ($LASTEXITCODE -ne 0) {
        Write-Log "WARNING: Failed to drop users from dev database with exit code $LASTEXITCODE." "WARN"
    } else {
        Write-Log "Users dropped successfully."
    }
} catch {
    Write-Log "WARNING: Could not drop users from dev database - $_" "WARN"
}



Write-Log "Schema deployment started..."

# Ensure SchemaDacpacFile is defined for standalone execution
if (-not (Get-Variable -Name SchemaDacpacFile -Scope Global -ErrorAction SilentlyContinue)) {
    Write-Log "SchemaDacpacFile not found. Searching for the latest DACPAC in $prodBackupFolder."
    $latestDacpac = Get-ChildItem -Path $prodBackupFolder -Filter "*.dacpac" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestDacpac) {
        $global:SchemaDacpacFile = $latestDacpac.FullName
        Write-Log "Using latest DACPAC file: $global:SchemaDacpacFile"
    } else {
        Write-Log "ERROR: No DACPAC file found in $prodBackupFolder. Cannot proceed with schema deployment." "ERROR"
        exit 1
    }
}

try {
    $LASTEXITCODE = 0 # Reset exit code
    $sqlPackageArgs = @(
        "/Action:Publish",
        "/SourceFile:$global:SchemaDacpacFile",
        "/TargetServerName:$DEV_SERVER",
        "/TargetDatabaseName:$DEV_DATABASE",
        "/TargetUser:$DEV_USER",
        "/TargetPassword:$DEV_PASSWORD",
        "/TargetTrustServerCertificate:True",
        "/p:DropObjectsNotInSource=True"
    )
    & "$SQLPACKAGE_PATH" @sqlPackageArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: SqlPackage.exe DACPAC publish failed with exit code $LASTEXITCODE." "ERROR"
        exit 1
    }
    Write-Log "Schema deployment completed successfully into [$DEV_DATABASE]."
} catch {
    Write-Log "ERROR: Schema deployment failed - $_" "ERROR"
    exit 1
}



# ---------- Step 3.2: Import Data for Selected Tables using BCP ----------

if (-not $maskingConfig.SkipDataImport -and (($maskingConfig.PSObject.Properties.Name -contains 'tablesToExcludeData') -or ($maskingConfig.PSObject.Properties.Name -contains 'tablesToRestoreData'))) { # Check if data import is enabled and if exclusion or inclusion is defined

    Write-Log "Step 3.2: Importing data for selected tables using BCP."

    if (-not (Test-Path $global:TempDataFolder)) {

        Write-Log "ERROR: Temporary data folder '$global:TempDataFolder' not found. Skipping data import." "ERROR"

        exit 1

    }



    # Get all user tables from the development database (schema should already be imported)

    $allDevTablesQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_CATALOG = '$DEV_DATABASE' AND TABLE_SCHEMA = 'dbo';"

    try {
        $LASTEXITCODE = 0 # Reset exit code
        $allDevTables = sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -d $DEV_DATABASE -Q $allDevTablesQuery -h -1 | Where-Object { $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) }

        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: sqlcmd failed to retrieve all table names from development database with exit code $LASTEXITCODE." "ERROR"
            exit 1
        }
    } catch {
        Write-Log "ERROR: Could not retrieve all table names from development database. - $_" "ERROR"
        exit 1
    }



        $tablesToImportData = @()



        if ($maskingConfig.tablesToRestoreData -and $maskingConfig.tablesToRestoreData.Count -gt 0) { # Whitelist approach



            $tablesToImportData = $allDevTables | Where-Object { $_ -in $maskingConfig.tablesToRestoreData }



            Write-Log "Using whitelist approach. Tables to import data: $($tablesToImportData -join ', ')"



        } elseif ($maskingConfig.PSObject.Properties.Name -contains 'tablesToExcludeData') { # Blacklist approach



            $tablesToImportData = $allDevTables | Where-Object { $_ -notin $maskingConfig.tablesToExcludeData }



            Write-Log "Using blacklist approach. Tables to import data: $($tablesToImportData -join ', ')"



        }



    foreach ($tableName in $tablesToImportData) {

        $dataFile = "$global:TempDataFolder/$tableName.csv"

        if (!(Test-Path $dataFile)) {

            Write-Log "WARNING: Data file '$dataFile' for table '$tableName' not found. Skipping import for this table." "WARN"

            continue

        }

        Write-Log "Importing data for table '$tableName' from '$dataFile'..."

        try {
            $LASTEXITCODE = 0 # Reset exit code
            # bcp command: [database].[schema].[table] in [datafile] -c -t, -S [server] -U [user] -P [password]
            & bcp "$DEV_DATABASE.dbo.$tableName" in "$dataFile" -n -S "$DEV_SERVER" -U "$DEV_USER" -P "$DEV_PASSWORD" -q

            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: BCP data import for table '$tableName' failed with exit code $LASTEXITCODE." "ERROR"
                exit 1
            }
            Write-Log "Data import for table '$tableName' completed successfully."
        } catch {
            Write-Log "ERROR: BCP data import for table '$tableName' failed - $_" "ERROR"
            exit 1
        }

    }

    Write-Log "Data import for all selected tables completed successfully."

} else {

    Write-Log "No tables specified for data import (neither whitelist nor blacklist). Skipping data import." "INFO"

}



. "$PSScriptRoot/Invoke-DataMasking.ps1"



# ---------- Step 5: Clear Temporary Files (copied from Clear-TempFiles.ps1) ----------

Write-Log "Step 5: Checking for temporary data files to clear."



if (Test-Path $global:TempDataFolder) {
    Write-Log "Temporary data folder '$global:TempDataFolder' not cleared as per user's choice." "INFO"
} else {
    Write-Log "Temporary data folder '$global:TempDataFolder' not found. Nothing to clear." "INFO"
}



Write-Log "Backup & Restore process completed successfully."