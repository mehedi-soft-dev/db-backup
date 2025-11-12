# ===============================================
# PowerShell Script: Backup & Restore via DACPAC and BCP
# Author: Md. Mehedi Hasan
# Date: 2025-11-06
# ===============================================

# ---------- Execute Steps ----------
. "$PSScriptRoot/Export-SchemaAndData.ps1"
. "$PSScriptRoot/Import-SchemaAndData.ps1"

Write-Log "Backup & Restore process completed successfully."