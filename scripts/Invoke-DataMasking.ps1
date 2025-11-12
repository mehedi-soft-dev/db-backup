# Load dependencies
. "$PSScriptRoot/Find-ConfigFile.ps1"
. "$PSScriptRoot/Write-Log.ps1"

# ---------- Foreign Key Management Functions ----------
function Disable-ForeignKeys {
    param (
        [string]$Server,
        [string]$Database,
        [string]$User,
        [string]$Password
    )
    Write-Log "Disabling all foreign key constraints in database '$Database'..."
    try {
        $query = @"
SELECT 'ALTER TABLE [' + s.name + '].[' + t.name + '] NOCHECK CONSTRAINT [' + fk.name + '];'
FROM sys.foreign_keys fk
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id;
"@
        $commands = sqlcmd -S $Server -U $User -P $Password -d $Database -Q $query -h -1 | Where-Object { $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) }

        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: sqlcmd failed to retrieve foreign key disable commands with exit code $LASTEXITCODE." "ERROR"
            return $false
        }

        foreach ($cmd in $commands) {
            Write-Log "Executing: $cmd"
            sqlcmd -S $Server -U $User -P $Password -d $Database -Q $cmd | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: Failed to disable foreign key with command '$cmd' (exit code $LASTEXITCODE)." "ERROR"
                return $false
            }
        }
        Write-Log "All foreign key constraints disabled successfully."
        return $true
    } catch {
        Write-Log "ERROR: Failed to disable foreign key constraints. - $_" "ERROR"
        return $false
    }
}

function Enable-ForeignKeys {
    param (
        [string]$Server,
        [string]$Database,
        [string]$User,
        [string]$Password
    )
    Write-Log "Enabling all foreign key constraints in database '$Database'..."
    try {
        $query = @"
SELECT 'ALTER TABLE [' + s.name + '].[' + t.name + '] CHECK CONSTRAINT [' + fk.name + '];'
FROM sys.foreign_keys fk
INNER JOIN sys.tables t ON fk.parent_object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id;
"@
        $commands = sqlcmd -S $Server -U $User -P $Password -d $Database -Q $query -h -1 | Where-Object { $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) }

        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: sqlcmd failed to retrieve foreign key enable commands with exit code $LASTEXITCODE." "ERROR"
            return $false
        }

        foreach ($cmd in $commands) {
            Write-Log "Executing: $cmd"
            sqlcmd -S $Server -U $User -P $Password -d $Database -Q $cmd | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: Failed to enable foreign key with command '$cmd' (exit code $LASTEXITCODE)." "ERROR"
                return $false
            }
        }
        Write-Log "All foreign key constraints enabled successfully."
        return $true
    } catch {
        Write-Log "ERROR: Failed to enable foreign key constraints. - $_" "ERROR"
        return $false
    }
}

# ===================================================================
# HARDCODED FOR DEBUGGING - START
# ===================================================================
$PROD_DATABASE="nextXdb"
$DEV_DATABASE="nextXdb_dev"
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

# ---------- Load Masking Configuration ----------
$maskingConfigFile = Find-ConfigFile -fileName "$($PROD_DATABASE)_config.json"
if (-not $maskingConfigFile) {
    Write-Log "WARNING: masking-config.json not found. Cannot import selective table data." "WARN"
    $maskingConfig = @{} # Empty config to avoid errors
} else {
    $maskingConfig = Get-Content $maskingConfigFile | ConvertFrom-Json
}

# ---------- Get Temp Folder ----------
# This logic is primarily for when the script is run standalone.
# If called from Import-SchemaAndData.ps1, $global:TempDataFolder should already be set.
if (-not $global:TempDataFolder) {
    $prodBackupFolder = Join-Path -Path $BACKUP_FOLDER -ChildPath $PROD_DATABASE
    $lastTempFile = Join-Path -Path $prodBackupFolder -ChildPath "last_temp_folder.txt"
    $global:TempDataFolder = Get-Content $lastTempFile -ErrorAction SilentlyContinue
}

# Ensure the temporary data folder exists
if (-not (Test-Path -Path $global:TempDataFolder -PathType Container)) {
    # If it still doesn't exist, we can't proceed.
    Write-Log "ERROR: Temporary data folder not found at '$($global:TempDataFolder)'. This folder is created by the export script." "ERROR"
    exit 1
}


# ---------- Data Masking Functions ----------
function Get-FakeName {
    $firstNames = "John", "Jane", "Peter", "Mary", "David", "Sarah", "Chris", "Anna", "James", "Linda", "Robert", "Maria", "Susan", "Daniel", "Nancy", "Paul", "Karen", "Mark", "Betty", "Laura", "Kevin"
    $lastNames = "Smith", "Jones", "Brown", "Davis", "Miller", "Wilson", "Moore", "Taylor", "White", "Harris", "Martin", "Lewis", "Lee", "Walker", "Hall", "Allen", "Young", "King", "Wright", "Lopez", "Hill", "Scott", "Green", "Adams", "Baker"
    $firstName = Get-Random -InputObject $firstNames
    $lastName = Get-Random -InputObject $lastNames
    return "$firstName $lastName"
}

function Get-FakeEmail {
    $domains = "example.com", "test.org", "mail.net"
    $namePart = (Get-FakeName).Replace(" ", ".").ToLower() # Use fake name, replace space with dot, lowercase
    $randomNumber = Get-Random -Minimum 10 -Maximum 99
    $domain = Get-Random -InputObject $domains
    return "$namePart$randomNumber@$domain"
}

function Get-FakeMobile {
    # Generate a 7-digit number to make it invalid as a typical 10-digit mobile number
    return -join (1..7 | ForEach-Object { Get-Random -Minimum 0 -Maximum 9 })
}

function Get-FakeAddress {
    param($index)
    return "Masked Address $index"
}

# ---------- Spinner Helper Function ----------
function Get-SpinnerChar {
    param(
        [int]$Index
    )
    $spinnerChars = @('|', '/', '-', '\')
    return $spinnerChars[$Index % $spinnerChars.Length]
}

# ---------- Invoke Data Masking ----------
Write-Log "Step 4: Starting Data Masking"

# Check if data masking should be skipped
if ($maskingConfig.SkipDataMasking -eq $true) {
    Write-Log "SkipDataMasking is set to true. Skipping data masking process."
    exit 0
}

# Foreign key constraints are not explicitly disabled/enabled as per user request.

# ---------- Process Masking Rules (BCP Export, Mask in File, BCP Import) ----------
Write-Log "Starting data masking process for all configured tables..."
$totalTables = $maskingConfig.tables.Count
$tableCounter = 0
foreach ($table in $maskingConfig.tables) {
    $tableCounter++
    $tableName = $table.name
    $spinnerIndex = $tableCounter % 4 # Cycle through 0, 1, 2, 3
    $spinnerChar = Get-SpinnerChar -Index $spinnerIndex
    Write-Progress -Activity "Data Masking" -Status "Processing table: $tableName $spinnerChar" -PercentComplete (($tableCounter / $totalTables) * 100) -Id 1


    # ---------- In-place Data Masking using UPDATE statements (Hybrid BCP Export + PowerShell Masking + SQL UPDATE) ----------
    Write-Log "Masking data in table '$tableName' using in-place UPDATE statements (Hybrid BCP Export/Mask/Update)..."
    # Targeting server and database details are not logged in final version.
    try {
        $uniqueIdentifierColumn = $table.uniqueIdentifierColumn
        if (-not $uniqueIdentifierColumn) {
            Write-Log "WARNING: 'uniqueIdentifierColumn' not defined for table '$tableName'. Cannot perform in-place update. Skipping masking." "WARN"
            return # Use return instead of continue to exit the current table processing
        }

        $columnsToMaskConfig = $table.columns
        if (-not $columnsToMaskConfig) {
            Write-Log "INFO: No columns configured for masking in table '$tableName'. Skipping in-place update." "INFO"
            return
        }

        # Get all column names (unique identifier + columns to mask) for BCP export
        $allColumnsForExport = @($uniqueIdentifierColumn)
        foreach ($col in $columnsToMaskConfig) {
            $allColumnsForExport += $col.name
        }
        $selectColumnsForBcp = ($allColumnsForExport | ForEach-Object { "[$_]" }) -join ','

        # 1. BCP Export data to a temporary file
        $tempExportFile = Join-Path -Path $global:TempDataFolder -ChildPath "$tableName.temp.csv"
        $delimiter = "~!|!~" # Unique delimiter for BCP

        # Exporting data to temporary file for in-place masking (not logged in final version).
        $bcpCommand = "SELECT $selectColumnsForBcp FROM [$DEV_DATABASE].[dbo].[$tableName]"
        $bcpOutput = & bcp "$bcpCommand" queryout "$tempExportFile" -c -t "$delimiter" -r "~!ROWEND!~" -S "$DEV_SERVER" -U "$DEV_USER" -P "$DEV_PASSWORD" 2>&1 | Out-String
        # BCP export output is captured but not logged in final version.

                    if ($LASTEXITCODE -ne 0) {
                        Write-Log "ERROR: BCP export for table '$tableName' failed with exit code $LASTEXITCODE. Skipping masking. Output: $bcpOutput" "ERROR"
                        return
                    }
                    # Data exported to temporary file successfully (not logged in final version).
        # 2. Read, Mask, and Construct UPDATE statements
        # Reading temporary file and constructing UPDATE statements (not logged in final version).
        $csvContent = (Get-Content $tempExportFile -Raw) -split '~!ROWEND!~' | Where-Object { -not [string]::IsNullOrEmpty($_) }
        
        # BCP queryout with -c -t does not output header by default.
        # So we use $allColumnsForExport for column mapping.
        $fetchedColumnNames = $allColumnsForExport

        # Create a hash table for quick lookup of column index by name
        $columnIndexMap = @{}
        for ($idx = 0; $idx -lt $fetchedColumnNames.Length; $idx++) {
            $columnIndexMap[$fetchedColumnNames[$idx]] = $idx
        }

        $totalRows = $csvContent.Count
        $rowCounter = 0
        $i = 1 # Counter for Get-FakeName/Email/Address -index parameter
        foreach ($line in $csvContent) {
            $rowCounter++
            $spinnerIndex = $rowCounter % 4 # Cycle through 0, 1, 2, 3
            $spinnerChar = Get-SpinnerChar -Index $spinnerIndex
            Write-Progress -Activity "Masking rows in $tableName" -Status "Processing row $rowCounter of $totalRows $spinnerChar" -PercentComplete (($rowCounter / $totalRows) * 100) -Id 2
            $fields = $line -split $delimiter # Keep all fields, including empty ones
            
            # User requested to not check column count and update by ID, even if field count mismatches.
            # This might lead to incorrect masking if the split was truly wrong, but fulfills "don't skip".

            $updateSetClauses = @()
            $idValue = ""
            $idColumnType = "" # To determine if it needs quotes

            for ($colIndex = 0; $colIndex -lt $fetchedColumnNames.Count; $colIndex++) {
                $currentColumnName = $fetchedColumnNames[$colIndex]
                $currentColumnValue = $fields[$colIndex].Trim() # Trim spaces from BCP output

                if ($currentColumnName -eq $uniqueIdentifierColumn) {
                    $idValue = $currentColumnValue
                    # Attempt to determine if ID is numeric or string for quoting
                    # Check for GUID pattern or simple integer
                    if ($currentColumnValue -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -or $currentColumnValue -match '^\d+$') {
                        $idColumnType = "string" # Treat GUIDs and potentially large numbers as strings for quoting
                    } else {
                        $idColumnType = "string" # Default to string
                    }
                    continue
                }

                $maskingConfigForColumn = $columnsToMaskConfig | Where-Object { $_.name -eq $currentColumnName } | Select-Object -First 1
                if ($maskingConfigForColumn) {
                    $maskingType = $maskingConfigForColumn.maskingType
                    $fakeData = ""
                    switch ($maskingType) {
                        "name"    { $fakeData = Get-FakeName }
                        "email"   { $fakeData = Get-FakeEmail }
                        "mobile"  { $fakeData = Get-FakeMobile }
                        "address" { $fakeData = Get-FakeAddress -index $i }
                        default   {
                            Write-Log "WARNING: Unknown masking type '$maskingType' for column '$currentColumnName' in table '$tableName'. Skipping masking for this column." "WARN"
                            continue
                        }
                    }
                    $updateSetClauses += "[$currentColumnName] = N'$($fakeData -replace "'","''")'" # Escape single quotes
                }
            }

            if ($updateSetClauses.Count -gt 0 -and -not [string]::IsNullOrEmpty($idValue)) {
                $quotedIdValue = if ($idColumnType -eq "string") { "'$($idValue -replace "'","''")'" } else { $idValue }
                $updateQuery = "UPDATE [$tableName] SET $($updateSetClauses -join ', ') WHERE [$uniqueIdentifierColumn] = $quotedIdValue;"
                
                                                                    $tempSqlFile = Join-Path -Path $global:TempDataFolder -ChildPath "update_$tableName_$idValue.sql"
                
                                                                    Set-Content -Path $tempSqlFile -Value $updateQuery -Encoding UTF8
                
                                                    
                
                                                                    try {
                
                                                                        $sqlcmdOutput = sqlcmd -S $DEV_SERVER -U $DEV_USER -P $DEV_PASSWORD -d $DEV_DATABASE -i "$tempSqlFile" 2>&1 | Out-String
                
                                                                        if ($LASTEXITCODE -ne 0) {
                
                                                                            Write-Log "ERROR: Failed to update row with $uniqueIdentifierColumn = '$idValue' in table '$tableName' (exit code $LASTEXITCODE). SQLCMD Output: $sqlcmdOutput" "ERROR"
                
                                                                        }
                
                                                                    } finally {
                
                                                                        if (Test-Path -Path $tempSqlFile) {
                
                                                                            Remove-Item -Path $tempSqlFile -ErrorAction SilentlyContinue
                
                                                                        }
                
                                                                    }            }
            $i++
        }
        Write-Progress -Activity "Masking rows in $tableName" -Status "Completed rows for $tableName." -PercentComplete 100 -Completed -Id 2
        Write-Log "In-place data masking completed for table '$tableName'."
    } catch { # Catch for the entire table masking process
        Write-Log "ERROR: Failed to perform in-place data masking for table '$tableName'. Skipping. - $_" "ERROR"
    } finally { # Finally for the entire table masking process
        # Clean up temporary file
        if (Test-Path -Path $tempExportFile) {
            Remove-Item -Path $tempExportFile -ErrorAction SilentlyContinue
            Write-Log "Cleaned up temporary file: $tempExportFile"
        } # This closes the 'if (Test-Path -Path $tempExportFile)'
    } # This closes the 'finally' block
    Write-Log "Finished masking table: $tableName"
} # This closes the 'foreach ($table in $maskingConfig.tables)' loop.
Write-Progress -Activity "Data Masking" -Status "Completed all tables." -PercentComplete 100 -Completed -Id 1

# Foreign key constraints are not explicitly disabled/enabled as per user request.

Write-Log "Data Masking process completed."