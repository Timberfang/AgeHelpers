function ConvertTo-OPUS {
    <#
    .SYNOPSIS
        Encodes an audio file using OPUS encoding
    .DESCRIPTION
        A longer description of the function, its purpose, common use cases, etc.
    .NOTES
        For this function to work correctly, ffmpeg must be available on the PATH. This program may be downloaded at https://ffmpeg.org.
    .PARAMETER Path
        A path to a file or folder.
    .PARAMETER Destination
        A path to a file or folder. If a folder was used for the input, a folder must be used for the output.
    .PARAMETER Filter
        An array of one or more file extensions to treat as audio files. By default, it searches for most common file extensions for audio.
    .PARAMETER Bitrate
        Select the bitrate for audio encoding, in kilobits per second.

        The developers of the OPUS codec recommend bitrates for different use cases; these recommendations are available at https://wiki.xiph.org/Opus_Recommended_Settings
    .PARAMETER NoSurround
        Disables surround sound. If the input is already in stereo, this parameter has no effect.
    .EXAMPLE
        Get-Item 'C:\Users\ExampleUser\Music\Input.mp3' | ConvertTo-Opus -Destination 'C:\Users\ExampleUser\ProcessedMusic\Output.opus'
        Encode a single audio file.
    .EXAMPLE
        Get-ChildItem 'C:\Users\ExampleUser\Music' -File -Recurse | ConvertTo-AV1 -Destination 'C:\Users\ExampleUser\ProcessedMusic'
        Encode a directory of audio files.
    #>

    [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [Parameter()]
        [string[]]
        $Filter = @('.mp3', '.wav', '.flac', '.ogg'),

        [Parameter()]
        [int]
        $Bitrate = 96,

        [Parameter()]
        [switch]
        $NoSurround
    )

    begin {
        Set-StrictMode -Version 3

        # Test if external commands are available
        Write-Verbose 'Checking for ffmpeg'
        if ($null -eq (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)) { throw 'Cannot find ffmpeg on system PATH' }

        # Assume destination path without extension is meant to be a directory
        # May not always be valid, but I don't know of any better methods
        Write-Verbose 'Checking if destination is a directory'
        if ((Split-Path $Destination -Extension) -eq "") {
            $IsDirectory = $true
            try { New-Item -Path $Destination -ItemType Directory -Force | Out-Null }
            catch { throw 'Failed to create output directory.' }
        }
        else { $IsDirectory = $false }

        # Convert bitrate to kilobits per second
        $Bitrate = $Bitrate * 1000
        Write-Verbose "Bitrate: $Bitrate"
    }

    process {
        # Validate inputs
        Write-Information "[$(Get-Date -Format yyyy-MM-dd-HH:MM)] Preparing input..." -InformationAction Continue
        Write-Verbose 'Validating inputs'
        if (!(Test-Path $Path -PathType Leaf)) {
            Write-Error "Path '$Path' is a directory or does not exist, skipping file..."
            Return
        }
        else { Write-Verbose "Path '$Path' exists" }
        if ($Path.Extension -notin $Filter) {
            Write-Verbose "File '$Path' not in filter list $Filter, skipping file..."
            Return
        }
        if ($IsDirectory) {
            $Target = Join-Path $Destination ([IO.Path]::ChangeExtension($Path.Name, '.opus'))
            Write-Verbose "Path '$Destination' is a directory"
        }
        else {
            $Target = [IO.Path]::ChangeExtension($Destination, '.opus')
            Write-Verbose "Path '$Destination' is a file"
        }
        if (Test-Path $Target) {
            Write-Error -Message "Path '$Target' exists, skipping file..."
            Return
        }

        # Set up ffmpeg arguments
        $FFMpegParams = @(
            '-i', $Path.FullName,
            '-c:a', 'libopus',
            '-b:a', $AudioBitrate,
            '-af', 'aformat=channel_layouts=7.1|5.1|stereo' # Workaround for a bug with opus in ffmpeg, see https://trac.ffmpeg.org/ticket/5718
        )
        if ($NoSurround) {
            Write-Verbose 'Using stereo sound'
            $FFMpegParams += @('-ac', 2)
        }

        # Encode
        Write-Information "[$(Get-Date -Format yyyy-MM-dd-HH:MM)] Encoding '$Path'..." -InformationAction Continue
        New-Item (Split-Path $Target -Parent) -ItemType Directory -Force | Out-Null
        & ffmpeg @FFMpegParams $Target -loglevel error -stats
        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message "ffmpeg failed to encode '$Path', deleting target file at '$Target'..."
            if (Test-Path $Target) { Remove-Item $Target }
            Return
        }
    }
}
