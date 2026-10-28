# Remove-OldDotNETRuntimes

Removes outdated Microsoft Windows Desktop Runtime versions, keeping the latest per major version and architecture.

## Background

By default, .NET removes previous versions when a newer one is installed. This behavior is controlled through the `RemovePreviousVersion` registry value (`REG_SZ`), set either for all .NET versions or for a specific version:

| .NET version | Registry key                              | Name                    | Type     |
|--------------|-------------------------------------------|-------------------------|----------|
| All          | `HKLM\SOFTWARE\Microsoft\.NET`            | `RemovePreviousVersion` | `REG_SZ` |
| .NET 10      | `HKLM\SOFTWARE\Microsoft\.NET\10.0`       | `RemovePreviousVersion` | `REG_SZ` |
| .NET 9       | `HKLM\SOFTWARE\Microsoft\.NET\9.0`        | `RemovePreviousVersion` | `REG_SZ` |
| .NET 8       | `HKLM\SOFTWARE\Microsoft\.NET\8.0`        | `RemovePreviousVersion` | `REG_SZ` |

Accepted values:

| Value         | Behavior                                                                                    |
|---------------|---------------------------------------------------------------------------------------------|
| `always`      | Removes previous installations after the new version is installed (default).                |
| `never`       | Keeps previous installations; they must be removed manually.                                |
| `nextSession` | Defers removal until the next logon session of a member of the Administrators group.        |

Values are case-insensitive and invalid values default to `always`.

See [Choose when previous versions are removed](https://learn.microsoft.com/en-us/dotnet/core/install/windows#choose-when-previous-versions-are-removed) on Microsoft Learn.

## What the script does

When `RemovePreviousVersion` is set to `never` (or `nextSession`), older runtimes remain on the machine. This script performs that cleanup in a controlled way, independent of the .NET installer, and with no need for an Administrator to log on (unlike `nextSession`).

1. Reads the installed programs from the registry Uninstall keys.
2. Finds all "Microsoft Windows Desktop Runtime" entries.
3. Groups them per major version (e.g. 6, 7, 8) and per architecture (x86 and x64). The architecture is determined from the `DisplayName`, because the registry reports all .NET entries as 32-bit.
4. Keeps the newest build in each group and silently uninstalls all older builds without restart.

## Logging

Every action (success, reboot required, failure, skipped entry) is logged to:

```
%windir%\Logs\Remove-OldDotNETRuntimes.log
```

## Requirements

- Administrative privileges

## Deployment

Intended to run as a startup script via Group Policy:

**Computer Configuration > Policies > Windows Settings > Scripts > Startup**

The script then runs as SYSTEM and has the required privileges. No Administrator logon is needed for the cleanup to take place.

## Usage

```powershell
.\Remove-OldDotNETRuntimes.ps1
```

## Author

Matthijs Koers