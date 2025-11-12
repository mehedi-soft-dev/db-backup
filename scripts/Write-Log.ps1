# ---------- Logging Function ----------
function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $entry = "[{0}][{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $entry

    # Only write to file if BACKUP_FOLDER is defined
    if ([string]::IsNullOrEmpty($BACKUP_FOLDER)) {
        return
    }

    $logDir = $BACKUP_FOLDER
    if ($global:LogDatabaseName) {
        $logDir = Join-Path -Path $BACKUP_FOLDER -ChildPath $global:LogDatabaseName
    }

    if (-not (Test-Path -Path $logDir -PathType Container)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $LogFile = Join-Path -Path $logDir -ChildPath "BackupRestoreLog.txt"
    Add-Content -Path $LogFile -Value $entry
}