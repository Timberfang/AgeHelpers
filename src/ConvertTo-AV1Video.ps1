function ConvertTo-AV1Video {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.IO.FileInfo]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [Parameter()]
        [string[]]
        $Filter = @('.mkv', '.webm', '.mp4', '.m4v', '.m4a', '.avi', '.mov', '.qt', '.ogv', '.ogg'),

        [Parameter()]
        [ValidateSet('Standard', 'High')]
        [string]
        $Preset = 'Standard',

        [Parameter()]
        [switch]
        $NoCrop,

        [Parameter()]
        [switch]
        $NoSurround
    )

    begin {
        Set-StrictMode -Version 3

        # Test if external commands are available
        Write-Verbose 'Checking for ffmpeg and ffprobe'
        if ($null -eq (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)) { throw 'Cannot find ffmpeg on system PATH' }
        if ($null -eq (Get-Command 'ffprobe' -ErrorAction SilentlyContinue)) { throw 'Cannot find ffprobe on system PATH' }

        # Assume destination path without extension is meant to be a directory
        # May not always be valid, but I don't know of any better methods
        Write-Verbose 'Checking if destination is a directory'
        if ((Split-Path $Destination -Extension) -eq "") {
            $IsDirectory = $true
            try { New-Item -Path $Destination -ItemType Directory -Force | Out-Null }
            catch { throw 'Failed to create output directory.' }
        }
        else { $IsDirectory = $false }

        # Handle preset
        switch ($Preset) {
            'High' {
                $VideoQuality = 27
                $VideoPreset = 6
                $AudioBitrate = 128000
            }
            Default {
                $VideoQuality = 33
                $VideoPreset = 10
                $AudioBitrate = 96000
                $NoSurround = $true
            }
        }
        Write-Verbose "Video CRF: $VideoQuality; Video Preset: $VideoPreset; Audio Bitrate: $AudioBitrate; Keep Channels: $(!$NoSurround)"

        # Handles SVT_LOG environment variable - used to block SVT-AV1's output
        Write-Verbose 'Silencing the AV1 encoder'
        $SVTConfigPath = Join-Path 'env:' 'SVT_LOG'
        $SVTConfig = Test-Path $SVTConfigPath
        if ($SVTConfig) { $SVTValue = Get-Item $SVTConfigPath | Select-Object -ExpandProperty Value }
        $env:SVT_LOG = 1
    }

    process {
        # Validate inputs
        Write-Information "[$(Get-Date -Format yyyy-MM-dd-HH:MM)] Preparing input..." -InformationAction Continue
        Write-Verbose 'Validating inputs'
        if (!(Test-Path $Path -PathType Leaf)) {
            Write-Error "Path '$Path' is a directory or does not exist, skipping file..."
            Continue
        }
        else { Write-Verbose "Path '$Path' exists" }
        if ($Path.Extension -notin $Filter) {
            Write-Verbose "File '$Path' not in filter list $Filter, skipping file..."
            Continue
        }
        if ($IsDirectory) {
            $Target = Join-Path $Destination $Path.Name
            Write-Verbose "Path '$Target' is a directory"
        }
        else {
            $Target = $Destination
            Write-Verbose "Path '$Target' is a file"
        }
        if (Test-Path $Target) {
            Write-Error -Message "Path '$Target' exists, skipping file..."
            Continue
        }
        if (!$NoSurround) {
            Write-Verbose 'Detecting channel count'
            [int]$Channels = & ffprobe -select_streams a:0 -show_entries stream=channels -of compact=p=0:nk=1 -v error $Path
            if ($LASTEXITCODE -ne 0) {
                Write-Error -Message "ffprobe failed to parse audio channels from file '$Path', skipping file..."
                Continue
            }
            switch ($Channels) {
                { $_ -ge 7 } { $AudioBitrate = 320000 }
                { ($_ -ge 5) -and ($_ -lt 7) } { $AudioBitrate = 256000 }
                { $_ -le 2 } { $AudioBitrate = 128000 }
                Default { Write-Error -Message "Unrecognized audio format. Defaulting to $AudioBitRate." }
            }
        }

        # Set up ffmpeg arguments
        $FFMpegParams = @(
            '-i', $Path.FullName,
            '-c:v', 'libsvtav1',
            '-crf', $VideoQuality,
            '-preset', $VideoPreset,
            '-c:a', 'libopus',
            '-b:a', $AudioBitrate,
            '-c:s', 'copy',
            '-af', 'aformat=channel_layouts=7.1|5.1|stereo' # Workaround for a bug with opus in ffmpeg, see https://trac.ffmpeg.org/ticket/5718
        )
        if (!$NoCrop) {
            Write-Verbose 'Detecting cropping dimensions'
            $CropData = & ffmpeg -skip_frame nokey -y -hide_banner -nostats -t 10:00 -i $Path -vf cropdetect -an -f null - 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error -Message "ffmpeg failed to run crop detection on file '$Path', skipping file..."
                Continue
            }
            $Crop = ($CropData | Select-String -Pattern 'crop=.*' | Select-Object -Last 1 ).Matches.Value
            $FFMpegParams += @('-vf', $Crop)
            Write-Verbose "Cropping config is $Crop"
        }
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
            Continue
        }
    }

    end {
        # Perform cleanup
        Write-Verbose 'Cleaning up leftovers'
        if ($SVTConfig) { $env:SVT_LOG = $SVTValue }
        else { Remove-Item $SVTConfigPath }
    }
}
