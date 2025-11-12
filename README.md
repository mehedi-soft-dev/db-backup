# SQL Backup & Restore Tool

A PowerShell-based tool for backing up and restoring SQL Server databases using DACPAC (schema) and BCP (data) methods with optional data masking.

## 📋 Prerequisites

- **Windows OS** with PowerShell
- **SQL Server** (Production and/or Development)
- **SqlPackage.exe** (included in `scripts/dirver/DAC/bin/` or install [Microsoft SQL Server Data-Tier Application Framework](https://aka.ms/dacfx))
- **sqlcmd** utility (comes with SQL Server)
- **SQL Server credentials** with appropriate permissions (CREATE DATABASE, READ/WRITE access)

## 🚀 Quick Start

### 1. Run the Tool

Simply double-click `run.bat` or execute from command line:

```cmd
run.bat
```

This will launch an interactive menu with the following options:

```
1. Full Backup and Restore to Dev
2. Only Export (Schema + Data from Production)
3. Only Import (Schema + Data to Development)
4. Only Masking (Apply data masking to exported data)
5. Clear Temporary Data (Clean up backup files)
Q. Quit
```

## ⚙️ Configuration

### Step 1: Configure `.env` File

The `.env` file is located in the `config` folder. This file contains database connection details and paths.

**Location:** `config/.env`

**Example:**

```env
# =====================
# MSSQL Backup & Restore
# =====================

# Production Database Settings
PROD_SERVER=localhost
PROD_USER=sa
PROD_PASSWORD='YourProductionPassword'
PROD_DATABASE=your_prod_db

# Development Database Settings
DEV_SERVER=localhost,1445
DEV_USER=sa
DEV_PASSWORD='YourDevPassword'
DEV_DATABASE=your_dev_db

# Backup and Tool Paths
BACKUP_FOLDER="./scripts/backups"
SQLPACKAGE_PATH="./scripts/dirver/DAC/bin/SqlPackage.exe"
```

**Configuration Details:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `PROD_SERVER` | Production SQL Server address | `localhost` or `192.168.1.100` or `server.domain.com` |
| `PROD_USER` | Production database username | `sa` |
| `PROD_PASSWORD` | Production database password | `'MyP@ssw0rd'` (use quotes if contains special characters) |
| `PROD_DATABASE` | Production database name | `my_production_db` |
| `DEV_SERVER` | Development SQL Server address | `localhost,1445` (with port) |
| `DEV_USER` | Development database username | `sa` |
| `DEV_PASSWORD` | Development database password | `'MyDevP@ss'` |
| `DEV_DATABASE` | Development database name | `my_dev_db` |
| `BACKUP_FOLDER` | Where to store backup files | `"./scripts/backups"` |
| `SQLPACKAGE_PATH` | Path to SqlPackage.exe | `"./scripts/dirver/DAC/bin/SqlPackage.exe"` |

### Step 2: Configure Database-Specific Config File

Each database needs its own configuration file for data masking and selective export.

**Naming Convention:** `{PROD_DATABASE}_config.json`

For example, if your `PROD_DATABASE=test_db`, create: `config/test_db_config.json`

**Location:** `config/{PROD_DATABASE}_config.json`

**Example:** `config/test_db_config.json`

```json
{
    "tablesToExcludeData": [
        "audit_logs",
        "system_logs"
    ],
    "SkipDataImport": false,
    "SkipDataMasking": true,
    "tables": [
        {
            "name": "users",
            "uniqueIdentifierColumn": "Id",
            "columns": [
                { "name": "FirstName", "maskingType": "name" },
                { "name": "LastName", "maskingType": "name" },
                { "name": "Email", "maskingType": "email" },
                { "name": "Phone", "maskingType": "phone" }
            ]
        },
        {
            "name": "customers",
            "uniqueIdentifierColumn": "CustomerId",
            "columns": [
                { "name": "CustomerName", "maskingType": "name" },
                { "name": "ContactEmail", "maskingType": "email" }
            ]
        }
    ]
}
```

**Configuration Details:**

| Parameter | Description | Values |
|-----------|-------------|--------|
| `tablesToExcludeData` | Tables to skip during data export (schema only) | Array of table names: `["table1", "table2"]` |
| `SkipDataImport` | Skip importing data entirely | `true` or `false` |
| `SkipDataMasking` | Disable data masking | `true` (disable) or `false` (enable) |
| `tables` | Tables with sensitive data to mask | Array of table configurations |
| `name` | Table name | e.g., `"users"` |
| `uniqueIdentifierColumn` | Primary key or unique identifier | e.g., `"Id"`, `"UserId"` |
| `columns` | Columns to mask | Array of column configurations |
| `name` | Column name | e.g., `"Email"`, `"FirstName"` |
| `maskingType` | Type of masking to apply | `"name"`, `"email"`, `"phone"`, `"address"`, `"ssn"`, `"creditcard"` |

### Available Masking Types

| Masking Type | Description | Example Output |
|--------------|-------------|----------------|
| `name` | Generates random full names | `John Smith`, `Jane Doe` |
| `email` | Generates random email addresses | `user123@example.com` |
| `phone` | Generates random phone numbers | `555-123-4567` |
| `address` | Generates random addresses | `123 Main St, City, ST 12345` |
| `ssn` | Generates random SSN format | `123-45-6789` |
| `creditcard` | Generates random credit card numbers | `4111-1111-1111-1111` |

## 📁 Directory Structure

```
db-backup/
│
├── config/
│   ├── .env                          # Main configuration file
│   ├── test_db_config.json           # Database-specific config (example)
│   └── nextXdb_config.json           # Another database config (example)
│
├── scripts/
│   ├── BackupRestore-NewMethod.ps1   # Main backup & restore script
│   ├── Export-SchemaAndData.ps1      # Export schema and data
│   ├── Import-SchemaAndData.ps1      # Import schema and data
│   ├── Invoke-DataMasking.ps1        # Data masking script
│   ├── Clear-TempFiles.ps1           # Clean up temporary files
│   ├── menu.ps1                      # Interactive menu
│   ├── Find-ConfigFile.ps1           # Config file finder utility
│   ├── Write-Log.ps1                 # Logging utility
│   ├── backups/                      # Backup storage (auto-created)
│   └── dirver/DAC/bin/               # SqlPackage.exe location
│
└── run.bat                           # Launch script
```

## 🔧 Usage Examples

### Example 1: Full Backup and Restore

1. Configure `.env` with your production and development database details
2. Create `{PROD_DATABASE}_config.json` in the `config` folder
3. Run `run.bat`
4. Select option `1` (Full Backup and Restore to Dev)

This will:
- Extract schema from production database
- Export all table data (except excluded tables)
- Apply data masking (if enabled)
- Create/restore development database
- Import all data

### Example 2: Export Only (for manual review)

1. Configure files as above
2. Run `run.bat`
3. Select option `2` (Only Export)

This will:
- Export schema to `.dacpac` file
- Export data to BCP files in `scripts/backups/{database}/TempData_{timestamp}/`

### Example 3: Enable Data Masking

In your `{PROD_DATABASE}_config.json`:

```json
{
    "SkipDataMasking": false,
    "tables": [
        {
            "name": "users",
            "uniqueIdentifierColumn": "Id",
            "columns": [
                { "name": "Email", "maskingType": "email" },
                { "name": "Phone", "maskingType": "phone" }
            ]
        }
    ]
}
```

Run option `1` or `4` to apply masking.

## 🔍 Troubleshooting

### Issue: "Database not found"
- Verify `PROD_SERVER` and `PROD_DATABASE` in `.env` are correct
- Test connection: `sqlcmd -S localhost -U sa -P 'YourPassword' -Q "SELECT DB_ID('your_db')"`

### Issue: "Config file not found"
- Ensure config file name matches pattern: `{PROD_DATABASE}_config.json`
- Check file is in `config` folder
- Example: If `PROD_DATABASE=test_db`, file should be `test_db_config.json`

### Issue: "Wrong database being backed up"
- Check for hardcoded values in scripts (should be removed)
- Verify `.env` has correct `PROD_DATABASE` value
- Restart `run.bat` after making changes

### Issue: "SqlPackage.exe not found"
- Verify `SQLPACKAGE_PATH` in `.env` points to correct location
- Download from: https://aka.ms/dacfx

### Issue: "Permission denied"
- Ensure SQL user has appropriate permissions:
  - `CREATE DATABASE` permission for dev server
  - `SELECT` permission on all tables for prod server
  - `INSERT` permission on all tables for dev server

## 📝 Logs

Logs are displayed in the console during execution with timestamps:

```
[2025-11-12 11:39:44][INFO] Executing Full Backup and Restore...
[2025-11-12 11:39:44][INFO] Production database [test_db] found.
[2025-11-12 11:39:45][INFO] Step 1.1: Extracting Schema-Only DACPAC...
```

## ⚠️ Important Notes

1. **Always test on non-production systems first**
2. **Backup your development database** before restoring
3. The import process **drops and recreates** the development database
4. Data masking is **one-way** - masked data cannot be unmasked
5. Large databases may take significant time to export/import
6. Ensure sufficient disk space in `BACKUP_FOLDER`

## 🤝 Support

For issues or questions, contact: **Md. Mehedi Hasan**

---

**Version:** 1.0  
**Last Updated:** November 2025
