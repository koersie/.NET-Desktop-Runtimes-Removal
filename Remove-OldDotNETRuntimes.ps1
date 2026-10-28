<#
    .SYNOPSIS
    Removes outdated Microsoft Windows Desktop Runtime versions, keeping the latest per major version and architecture.
 
    .DESCRIPTION
    Reads the installed programs from the registry Uninstall keys and finds all
    "Microsoft Windows Desktop Runtime" entries. For each major version (e.g. 6, 7, 8)
    and each architecture (x86 and x64, determined from the DisplayName because the
    registry reports all .NET entries as 32-bit), the newest build is kept and all
    older builds are uninstalled silently without restart.
 
    Every action (success, reboot required, failure, skipped entry) is logged to
    %windir%\Logs\Remove-OldDotNETRuntimes.log.
 
    .NOTES
    Author:   Matthijs Koers
    Requires: Administrative privileges
 
    .EXAMPLE
    .\Remove-OldDotNETRuntimes.ps1
#>
 
#Requires -RunAsAdministrator
 
Function Get-InstalledPrograms {
    <#
        .SYNOPSIS
        Lists installed programs from the registry Uninstall keys.

        .DESCRIPTION
        Reads the Uninstall registry keys and returns one object per installed program.
        By default only machine-wide (HKLM) installs are returned. Use -Scope to include
        per-user installs. Note that "User" reads HKCU, which is the profile of the
        account running the script, not necessarily the logged-on user.

        .PARAMETER Scope
        System (default): HKLM 64-bit and 32-bit keys.
        User: HKCU for the current account only.
        Both: System and User combined.

        .PARAMETER IncludeSystemComponents
        Include entries flagged SystemComponent=1, which are hidden from Programs and Features.

        .EXAMPLE
        Get-InstalledPrograms | Where-Object DisplayName -like '*Chrome*'

        .EXAMPLE
        Get-InstalledPrograms -Scope Both | Select-Object DisplayName, DisplayVersion, Publisher
    #>
    [CmdletBinding()]
    param (
        [ValidateSet("System", "User", "Both")]
        [string]$Scope = "System",

        [switch]$IncludeSystemComponents
    )

    $Locations = @()

    if ($Scope -in 'System', 'Both') {
        $Locations += @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';              Scope = 'System'; Arch = '64-bit' }
            @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*';  Scope = 'System'; Arch = '32-bit' }
        )
    }

    if ($Scope -in 'User', 'Both') {
        $Locations += @(
            @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'User'; Arch = 'Any' }
        )
    }

    $Properties = @(
        'AuthorizedCDFPrefix','Comments','Contact','DisplayName','DisplayVersion',
        'EstimatedSize','HelpLink','HelpTelephone','InstallDate','InstallLocation',
        'InstallSource','Language','ModifyPath','Publisher','Readme','Size',
        'SystemComponent','UninstallString','URLInfoAbout','URLUpdateInfo',
        'Version','VersionMajor','VersionMinor','WindowsInstaller'
    )

    $Results = foreach ($Location in $Locations) {
        Get-ItemProperty -Path $Location.Path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                ($IncludeSystemComponents -or $_.SystemComponent -ne 1)
            } |
            ForEach-Object {
                $Item = $_
                $Obj  = [ordered]@{}
                foreach ($Prop in $Properties) { $Obj[$Prop] = $Item.$Prop }
                $Obj['Scope']        = $Location.Scope
                $Obj['Architecture'] = $Location.Arch
                $Obj['RegistryKey']  = $Item.PSChildName
                [PSCustomObject]$Obj
            }
    }

    $Results | Sort-Object DisplayName, DisplayVersion
}
# Logging
$LogPath = "$env:windir\Logs\Remove-OldDotNETRuntimes.log"
 
Function Write-Log {
    param ([string]$Message)
    Add-Content -Path $LogPath -Value ("{0} {1}" -f (Get-Date -Format 'dd-MM-yyyy-HH:mm'), $Message)
}

# Get installed Desktop Runtime entries that have a usable version
$DesktopRuntimes = Get-InstalledPrograms |
    Where-Object { $_.DisplayName -match 'Microsoft Windows Desktop Runtime' -and ($_.DisplayVersion -as [version]) }
 
# Extract major versions
$MajorVersions = $DesktopRuntimes | ForEach-Object VersionMajor | Sort-Object -Unique

# Determine which applications to uninstall (everything except the newest build per major version and architecture
$ApplicationsToUninstall = @()
ForEach ($MajorVersion in $MajorVersions) {
    ForEach ($Architecture in '\(x86\)', '\(x64\)') {
        $ApplicationsToUninstall += $DesktopRuntimes |
            Where-Object { $_.DisplayName -match $Architecture -and $_.VersionMajor -eq $MajorVersion } |
            Sort-Object { [version]$_.DisplayVersion } -Descending |
            Select-Object -Skip 1
    }
}

# Uninstall old versions
ForEach($Application in $ApplicationsToUninstall){
    # Extract path
    $UninstallPath = $null
    If ($Application.UninstallString -match '^"([^"]+)"') {
        $UninstallPath = $matches[1]
    }

    If($UninstallPath -and (Test-Path -Path $UninstallPath -ErrorAction SilentlyContinue)) {
        $UninstallResult = Start-Process -FilePath $UninstallPath -ArgumentList "/uninstall /quiet /norestart" -Wait -PassThru

        Switch ($UninstallResult.ExitCode) {
            0       { Write-Log "$($Application.DisplayName) successfully uninstalled." }
            3010    { Write-Log "$($Application.DisplayName) successfully uninstalled (restart required)." }
            1641    { Write-Log "$($Application.DisplayName) successfully uninstalled (restart initiated)." }
            Default { Write-Log "$($Application.DisplayName) failed to uninstall. Exit code: $($UninstallResult.ExitCode)." }
        }
    }
    Else {
        Write-Log "$($Application.DisplayName) skipped: uninstaller not found or UninstallString could not be parsed."
    }

    # Clear variables
    Remove-Variable UninstallPath,UninstallResult -ErrorAction SilentlyContinue
}
