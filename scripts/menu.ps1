# ===============================================
# PowerShell Script: Interactive Menu for SQL Backup & Restore
# Author: Md. Mehedi Hasan
# Date: 2025-11-06
# ===============================================

# Load dependencies
. "$PSScriptRoot/Find-ConfigFile.ps1"
. "$PSScriptRoot/Write-Log.ps1"

function Show-Menu {
    param (
        [string]$MenuTitle = "SQL Backup & Restore Menu"
    )

    Clear-Host
    Write-Host "$MenuTitle" -ForegroundColor Cyan
    Write-Host "`n--------------------------------------------------`n" -ForegroundColor DarkGray

    # Display current configuration
    Write-Host "Current Configuration (from .env):" -ForegroundColor Yellow
    $envFile = Find-ConfigFile -fileName ".env"
    if ($envFile) {
        $envVars = Get-Content $envFile | Where-Object { $_ -match "^[^#].+=" }
        foreach ($line in $envVars) {
            $parts = $line -split '=',2
            $name = $parts[0].Trim()
            $value = $parts[1].Trim().Trim("'`"")
            if ($name -like "*PASSWORD*") {
                Write-Host "  $name = ********" -ForegroundColor Green
            } else {
                Write-Host "  $name = $value" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "  .env file not found." -ForegroundColor Red
    }
    Write-Host "`n--------------------------------------------------`n" -ForegroundColor DarkGray

    Write-Host "Masking Configuration:" -ForegroundColor Yellow
    # Load .env to get PROD_DATABASE for dynamic config file name
    $prodDbName = $null
    if ($envFile) {
        $prodDbLine = $envVars | Where-Object { $_ -match "^PROD_DATABASE=" }
        if ($prodDbLine) {
            $prodDbName = ($prodDbLine -split '=',2)[1].Trim().Trim("'`"")
        }
    }

    if ($prodDbName) {
        $maskingConfigFileName = "$($prodDbName)_config.json"
        $maskingConfigFile = Find-ConfigFile -fileName $maskingConfigFileName
        if ($maskingConfigFile) {
            Write-Host "  (from $maskingConfigFileName)" -ForegroundColor DarkGray
            $maskingConfig = Get-Content $maskingConfigFile | ConvertFrom-Json

            if ($maskingConfig.tablesToExcludeData) {
                Write-Host "  Exclude Tables: $($maskingConfig.tablesToExcludeData -join ', ')" -ForegroundColor Green
            } else {
                Write-Host "  No tables excluded from data export." -ForegroundColor DarkGreen
            }

            # Check if SkipDataMasking is true
            if ($maskingConfig.SkipDataMasking -eq $true) {
                Write-Host "  Data Masking: DISABLED (SkipDataMasking = true)" -ForegroundColor Yellow
            } else {
                # Show masking details only if not skipped
                if ($maskingConfig.tables) {
                    Write-Host "  Masked Tables and Columns:" -ForegroundColor Green
                    foreach ($table in $maskingConfig.tables) {
                        $maskedColumns = $table.columns | ForEach-Object { $_.name }
                        Write-Host "    - $($table.name): $($maskedColumns -join ', ')" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  No tables configured for masking." -ForegroundColor DarkGreen
                }
            }
        } else {
            Write-Host "  $maskingConfigFileName not found." -ForegroundColor Red
        }
    } else {
        Write-Host "  PROD_DATABASE not found in .env file. Cannot determine config file name." -ForegroundColor Red
    }
    Write-Host "`n--------------------------------------------------`n" -ForegroundColor DarkGray

    Write-Host "Please choose an option:" -ForegroundColor White
    Write-Host "1. Full Backup and Restore to Dev (runs BackupRestore-NewMethod.ps1)" -ForegroundColor White
    Write-Host "2. Only Export (runs Export-SchemaAndData.ps1)" -ForegroundColor White
    Write-Host "3. Only Import (runs Import-SchemaAndData.ps1)" -ForegroundColor White
    Write-Host "4. Only Masking (runs Invoke-DataMasking.ps1)" -ForegroundColor White
    Write-Host "5. Clear Temporary Data (runs Clear-TempFiles.ps1)" -ForegroundColor White
    Write-Host "Q. Quit" -ForegroundColor White
    Write-Host "`n--------------------------------------------------`n" -ForegroundColor DarkGray
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Enter your choice"

    switch ($choice) {
        "1" {
            Write-Log "Executing Full Backup and Restore..."
            & "$PSScriptRoot/BackupRestore-NewMethod.ps1"
            Read-Host "Press Enter to continue..."
        }
        "2" {
            Write-Log "Executing Only Export..."
            & "$PSScriptRoot/Export-SchemaAndData.ps1"
            Read-Host "Press Enter to continue..."
        }
        "3" {
            Write-Log "Executing Only Import..."
            & "$PSScriptRoot/Import-SchemaAndData.ps1"
            Read-Host "Press Enter to continue..."
        }
        "4" {
            Write-Log "Executing Only Masking..."
            & "$PSScriptRoot/Invoke-DataMasking.ps1"
            Read-Host "Press Enter to continue..."
        }
        "5" {
            Write-Log "Executing Clear Temporary Data..."
            & "$PSScriptRoot/Clear-TempFiles.ps1"
            Read-Host "Press Enter to continue..."
        }
        "q" {
            Write-Log "Exiting menu. Goodbye!"
            break
        }
        "Q" {
            Write-Log "Exiting menu. Goodbye!"
            break
        }
        default {
            Write-Log "Invalid choice. Please try again." "WARN"
            Read-Host "Press Enter to continue..."
        }
    }
}
