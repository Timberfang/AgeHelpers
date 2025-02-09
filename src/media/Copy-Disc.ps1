function Copy-Disc {
    <#
	.SYNOPSIS
		Back up all tracks from a disc to an mkv file.

	.DESCRIPTION
		A wrapper for MakeMKV and a set of pre-defined settings to back up all tracks from a disc. This can be useful for backing up a disc for use with services like Plex or Jellyfin.

		The output of the disc will be saved into a subfolder of the OutputPath, named after the disc title. If the directory does not exist, it will be created.

	.NOTES
		This function only works on Windows; a working MakeMKV installation with a valid license key (either free beta or purchased) must be available.

	.PARAMETER MakeMKVPath
		The path to makemkvcon64.exe.

	.PARAMETER OutputPath
		The path to which the output should be saved.

	.PARAMETER DriveIndex
		The drive index (i.e., 0 for the first drive, 1 for the second, etc.) for the drive to be used.

	.PARAMETER MinimumLength
		The minimum length of a track for it to be copied (this is to avoid backing up junk files).

	.PARAMETER CheckInterval
		The time in seconds to wait between checks for a new disc to be inserted.

	.PARAMETER Repeat
		If set, will continuously check for a new disc to be inserted after each backup completes.

	.EXAMPLE
		Copy-Disc -OutputPath 'C:\Users\ExampleUser\Videos\Family DVDs'
		Back up all tracks from a disc and save it to the path provided.
	#>

    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $MakeMKVPath = (Join-Path -Path ${Env:ProgramFiles(x86)} -ChildPath 'MakeMKV' | Join-Path -ChildPath 'bin' | Join-Path -ChildPath 'makemkvcon64.exe'),

        [Parameter(Mandatory)]
        [string]
        $OutputPath,

        [Parameter()]
        [int]
        $DriveIndex = 0,

        [Parameter()]
        [int]
        $MinimumLength = 30,

        [Parameter()]
        [int]
        $CheckInterval = 1,

        [Parameter()]
        [switch]
        $Repeat
    )

    begin {
        Set-StrictMode -Version 3

        # Backwards-compatible OS test
        if (([Environment]::OSVersion.Platform) -ne 'Win32NT') { throw 'This function is only compatible with Windows.' }

        # Get drive info
        $DriveInfo = Get-Volume | Where-Object DriveType -EQ 'CD-ROM' | Select-Object -First 1 -Skip $DriveIndex
        $TrayController = New-Object -ComObject Shell.Application

        # Test if inputs are available
        if (-not (Test-Path $MakeMKVPath -PathType Leaf)) { throw 'makemkvcon64.exe path is invalid or does not exist.' }
        if (-not $DriveInfo) { throw 'Optical drive not found. Please check if it is connected to your computer.' }
        if (-not (Test-Path $OutputPath -PathType Container)) {
            try { New-Item $OutputPath -ItemType Directory | Out-Null }
            catch { throw 'Failed to create output directory.' }
        }
    }

    process {
        do {
            # Check if disc is present
            $DiscName = Get-Volume | Where-Object DriveType -EQ 'CD-ROM' | Select-Object -First 1 -Skip $DriveIndex -ExpandProperty FileSystemLabel

            # If no disc is detected, wait for a disc to be inserted
            if ( -not $DiscName) {
                $TrayController.Namespace(17).ParseName($DriveInfo.DriveLetter + ':').InvokeVerb('Eject')
                Write-Verbose -Message 'Tray opened'

                # Wait loop
                Write-Information 'Waiting for disc to be inserted, press any key to exit...' -InformationAction Continue
                while ( -not $DiscName ) {
                    $KeyPressed = [System.Console]::KeyAvailable
                    if ($KeyPressed) { return }
                    Start-Sleep $SleepDuration
                    $DiscName = Get-Volume | Where-Object DriveType -EQ 'CD-ROM' | Select-Object -First 1 -Skip $DriveIndex -ExpandProperty FileSystemLabel
                }
            }
            Write-Verbose 'Disc detected'

            # Create target folder for disc
            [string]$Target = Join-Path -Path $OutputPath -ChildPath $DiscName
            for ($i = 1; Test-Path $Target; $i++) {
                [string]$Target = (Join-Path -Path $OutputPath -ChildPath ($DiscName + "-$i"))
                Write-Warning "Target directory already exists, trying {$Target}"
            }
            try { New-Item $Target -ItemType Directory | Out-Null }
            catch { throw 'Failed to create target directory.' }

            # Backup disc
            Write-Information "Backing up disc '$DiscName'" -InformationAction Continue
            & $MakeMKVPath mkv disc:$DriveIndex all --minlength=$MinimumLength $Target --progress=-stdout
            Write-Verbose 'Backup complete'

            # Open tray
            if ($Repeat) {
                $TrayController.Namespace(17).ParseName($DriveInfo.DriveLetter + ':').InvokeVerb('Eject')
                Write-Verbose 'Tray opened'
            }
        } while ($Repeat)
    }
}
