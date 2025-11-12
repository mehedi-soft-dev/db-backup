function Find-ConfigFile {
    param([string]$fileName)

    # First check in the config folder (relative to script's parent directory)
    $scriptDir = $PSScriptRoot
    if ($scriptDir) {
        $parentDir = Split-Path -Path $scriptDir -Parent
        $configDir = Join-Path -Path $parentDir -ChildPath "config"
        $filePath = Join-Path -Path $configDir -ChildPath $fileName
        if (Test-Path $filePath) {
            return $filePath
        }
    }

    # Then check current working directory's config folder
    $currentDir = Get-Location
    $configDir = Join-Path -Path $currentDir -ChildPath "config"
    $filePath = Join-Path -Path $configDir -ChildPath $fileName
    if (Test-Path $filePath) {
        return $filePath
    }

    # Search upward for config folder
    $rootDir = (Get-Location).Drive.Name + "\"
    $path = $currentDir
    while ($path -and $path -ne $rootDir) {
        $configDir = Join-Path -Path $path -ChildPath "config"
        $filePath = Join-Path -Path $configDir -ChildPath $fileName
        if (Test-Path $filePath) {
            return $filePath
        }
        $path = Split-Path -Path $path -Parent
        # Prevent infinite loop if Split-Path returns empty or same path
        if ([string]::IsNullOrWhiteSpace($path)) {
            break
        }
    }

    return $null
}