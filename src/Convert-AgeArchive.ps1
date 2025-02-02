function Convert-AgeArchive {
    <#
    .SYNOPSIS
        Encrypts a directory or file using age.
    .DESCRIPTION
        An interface around age (https://github.com/FiloSottile/age) for securely encrypting files and directories.

        Both age and tar must be available on the system PATH. Instructions to install age can be found at https://github.com/FiloSottile/age#installation.
        Tar is a standard Unix command line utility and can be found on most Linux and macOS systems.
        For Windows users, tar was added in Windows 10 build 17063 (April 2018 Update) and later; earlier versions of Windows are not supported.

        Convert-AgeArchive is provided without warranty of any kind.
        While all attempts have been made to not introduce vulnerabilities, please thoroughly test this function before using it for critical applications.
        The author is neither professional software developer nor a security expert.

        At its core, this function only provides a wrapper for age, passing the required arguments and using tar if necessary.
        The actual security is handled by age, and this function aims to not interfere with that in any way.
        Whenever possible, the practices outlined in age's official documentation and examples have been followed here.

        Please familiarize yourself with the security of age (and tar) before using Convert-AgeArchive.
    .NOTES
        This function does not currently support using multiple recipients, or reading recipients from a file.
    .PARAMETER Path
        The directory or file to encrypt.
    .PARAMETER Encrypt
        Select the encryption mode.
    .PARAMETER Decrypt
        Select the decryption mode.
    .PARAMETER Key
        Provide a key for key-pair authentication. This must be a valid age key file or ssh key file generated via age-keygen or ssh-keygen, respectively.
    .PARAMETER Delete
        Once successful encryption or decryption has completed, delete the original file or directory.
    .EXAMPLE
        Convert-AgeArchive -Path . -Encrypt
        Encrypts the current directory.
    .EXAMPLE
        Convert-AgeArchive -Path C:\Path\To\File.txt -Encrypt -Delete
        Encrypts the specified file and deletes the original.
    .EXAMPLE
        Convert-AgeArchive -Path C:\Path\To\File.age -Decrypt
        Decrypts the specified file.
    .EXAMPLE
        Convert-AgeArchive -Path C:\Path\To\File.age -Decrypt -Delete
        Decrypts the specified file and deletes the encrypted original.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path,

        [Parameter(Mandatory, ParameterSetName = 'Encrypt')]
        [switch]
        $Encrypt,

        [Parameter(Mandatory, ParameterSetName = 'Decrypt')]
        [switch]
        $Decrypt,

        [Parameter()]
        [string]
        $Key = $null,

        [Parameter()]
        [switch]
        $Delete
    )

    begin {
        Set-StrictMode -Version 3

        # Test if external commands are available
        if ($null -eq (Get-Command 'age' -ErrorAction SilentlyContinue)) { throw 'Error: age.exe not found on system PATH' }
        if ($null -eq (Get-Command 'tar' -ErrorAction SilentlyContinue)) { throw 'Error: tar.exe not found on system PATH' }

        # Process input
        if (!(Test-Path $Path)) { throw "Error: Path '$Path' not found." }
        if (($null -ne $Key) -and !(Test-Path $Key)) { throw "Error: Path '$Key' not found." }
        $Target = Get-Item $Path
        $IsDirectory = $Target.PSIsContainer -or $Target -like '*.tar.age'

        # Test if output already exists
        if ($Encrypt -and $IsDirectory) { $OutputPath = $Target.FullName + '.tar.age' }
        elseif ($Encrypt -and !$IsDirectory) { $OutputPath = $Target.FullName + '.age' }
        elseif ($Decrypt) { $OutputPath = $Target.FullName -replace '\.age' -replace '\.tar' } # -replace uses regex, so the '.' must be escaped
        if (Test-Path $OutputPath) { throw "Error: Path '$OutputPath' already exists." }
    }

    process {
        # Encrypt mode
        if ($Encrypt) {
            if ($null -ne $Key) {
                if ($IsDirectory) { & tar -c -C $Target.Parent $Target.Name | & age --encrypt -i $Key -o $OutputPath }
                else { & age --encrypt -i $Key -o $OutputPath $Target }
            }
            else {
                if ($IsDirectory) { & tar -c -C $Target.Parent $Target.Name | & age --encrypt -p -o $OutputPath }
                else { & age --encrypt -p -o $OutputPath $Target }
            }
        }

        # Decrypt mode
        elseif ($Decrypt) {
            if ($null -ne $Key) {
                if ($IsDirectory) { & age --decrypt -i $Key $Target | tar -x -C $Target.Directory }
                else { & age --decrypt -i $Key -o $OutputPath $Target }
            }
            else {
                if ($IsDirectory) { & age --decrypt $Target | tar -x -C $Target.Directory }
                else { & age --decrypt -o $OutputPath $Target }
            }
        }
    }

    end {
        if ($Delete) { Remove-Item $Target }
    }
}
