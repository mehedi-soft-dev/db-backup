# SQL Server Auto Backup and Restore with Data Masking

This project provides a set of PowerShell scripts to automate the backup of a SQL Server production database (schema and selected data), restore it to a development environment, and apply data masking to sensitive columns.

## Project Structure

```
.env
BackupRestore-NewMethod.ps1
Export-SchemaAndData.ps1
Find-ConfigFile.ps1
Import-SchemaAndData.ps1
Invoke-DataMasking.ps1
db_export_import_config.json
Write-Log.ps1
menu.ps1
run_menu.bat
README.md
```

## Setup and Configuration

### 1. Environment Variables (`.env`)

Create a file named `.env` in the root directory of the project. This file will store your database connection details and paths. **Ensure this file is secured and not committed to version control if it contains sensitive information.**

Example `.env` content:

```
PROD_SERVER=localhost,1440
PROD_USER=sa
PROD_PASSWORD='YourProdPassword'

DEV_SERVER=localhost,1445
DEV_USER=sa
DEV_PASSWORD='YourDevPassword'

PROD_DATABASE=YourProductionDBName
DEV_DATABASE=YourDevelopmentDBName

BACKUP_FOLDER="C:/sql-backups" # Folder to store DACPAC and BCP files
SQLPACKAGE_PATH="C:/Program Files/Microsoft SQL Server/170/DAC/bin/SqlPackage.exe" # Path to SqlPackage.exe
```

### 2. Data Export/Import and Masking Configuration (`db_export_import_config.json`)

This JSON file defines which tables' data should be exported/imported and which columns should be masked during the process.

*   `tablesToExcludeData`: An array of table names whose data should *not* be exported from production (blacklist approach). If `tablesToRestoreData` is present, this is ignored.
*   `tablesToRestoreData`: An array of table names whose data *should* be exported from production (whitelist approach). If present, `tablesToExcludeData` is ignored.
*   `tables`: An array of objects, each defining masking rules for a specific table.
    *   `name`: The name of the table.
    *   `uniqueIdentifierColumn`: The name of a column that uniquely identifies rows in the table (e.g., primary key). This is crucial for masking operations.
    *   `columns`: An array of objects, each defining a column to mask.
        *   `name`: The name of the column to mask.
        *   `maskingType`: The type of masking to apply. Supported types: `name`, `email`, `mobile`, `address`.

Example `db_export_import_config.json` content:

```json
{
    "tablesToExcludeData": [
        "Documents"
    ],
    "tables": [
        {
            "name": "AbpUsers",
            "uniqueIdentifierColumn": "Id",
            "columns": [
                { "name": "Name", "maskingType": "name" },
                { "name": "Email", "maskingType": "email" }
            ]
        },
        {
            "name": "NextXContacts",
            "uniqueIdentifierColumn": "Id",
            "columns": [
                { "name": "FirstName", "maskingType": "name" },
                { "name": "PhoneNumber", "maskingType": "mobile" }
            ]
        }
    ]
}
```

## How to Run

1.  **Ensure PowerShell Execution Policy:** If you encounter errors running PowerShell scripts, you might need to adjust your execution policy. Open PowerShell as Administrator and run:
    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```
    Or, for less secure but easier execution:
    ```powershell
    Set-ExecutionPolicy Bypass -Scope CurrentUser
    ```

2.  **Run the Menu:**
    *   **Using the batch file (recommended for ease of use):** Double-click `run_menu.bat` in the project root.
    *   **Using PowerShell directly:** Open PowerShell, navigate to the project root (`F:\office-project\sql-server-auto-backup\new-method`), and run:
        ```powershell
        .\menu.ps1
        ```

    The menu will display current configurations and provide options to perform different operations.

## Script Descriptions

*   `menu.ps1`: The main interactive menu script. It displays configuration, offers choices (full backup/restore, export, import, masking), and executes the corresponding scripts.
*   `run_menu.bat`: A simple batch file to easily launch `menu.ps1` by double-clicking.
*   `BackupRestore-NewMethod.ps1`: Orchestrates the full backup and restore process by sequentially calling `Export-SchemaAndData.ps1` and `Import-SchemaAndData.ps1`.
*   `Export-SchemaAndData.ps1`: Extracts the schema (DACPAC) and selected table data (BCP) from the production database.
*   `Import-SchemaAndData.ps1`: Prepares the development database, publishes the schema, imports selected data, and then calls the data masking script.
*   `Invoke-DataMasking.ps1`: Performs data masking on the development database using a BCP export-mask-import strategy for efficiency. Note: The `Get-FakeName` and `Get-FakeEmail` functions generate random data; they do not use an index to ensure uniqueness.
*   `Find-ConfigFile.ps1`: A helper function to locate configuration files (`.env`, `db_export_import_config.json`) by searching up the directory tree.
*   `Write-Log.ps1`: A logging utility that writes messages to both the console and a log file (`BackupRestoreLog.txt`) in the `BACKUP_FOLDER`.

## Error Handling

Scripts include robust error handling. Critical failures (e.g., database connection issues, DACPAC extraction/publish failures, BCP failures) will cause the script to exit immediately with an `ERROR` message. Warnings (e.g., `TRUNCATE TABLE` failing due to foreign keys) will be logged but may allow the script to attempt an alternative (like `DELETE FROM`).
