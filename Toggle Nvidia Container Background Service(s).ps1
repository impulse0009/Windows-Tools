#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Toggles the NVIDIA Display Container LS service.
.DESCRIPTION
    This script enables or disables the NVIDIA Display Container LS service,
    which affects the NVIDIA Control Panel functionality.
#>

$serviceName = "NVDisplay.ContainerLocalSystem"
$logFile = $PSCommandPath -replace '\.ps1$', '.log'

# Log messages to file and console
function Write-LogMessage {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Add-Content -Path $logFile
    Write-Verbose $Message
}

# Wait for user to press a key
function Wait-ForKeyPress {
    param([string]$Message)
    Write-Host $Message
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Get current state of NVIDIA service
function Get-NvidiaServiceState {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        return @{
            IsRunning = $service.Status -eq 'Running'
            IsAutomatic = $service.StartType -eq 'Automatic'
            Service = $service
        }
    }
    catch {
        Write-LogMessage "Error: Couldn't find the $serviceName service."
        throw
    }
}

# Wait for service to reach desired status
function Wait-ForServiceStatus {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.ServiceProcess.ServiceController]$Service,
        [Parameter(Mandatory=$true)]
        [string]$DesiredStatus,
        [int]$TimeoutSeconds = 5
    )
    try {
        $Service.WaitForStatus($DesiredStatus, [TimeSpan]::FromSeconds($TimeoutSeconds))
        return $true
    }
    catch {
        Write-LogMessage "Service didn't reach $DesiredStatus status within $TimeoutSeconds seconds."
        return $false
    }
}

# Toggle NVIDIA service state
function Set-NvidiaServiceState {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Enable', 'Disable')]
        [string]$Action,
        [hashtable]$State
    )

    Write-LogMessage "Trying to $Action the $serviceName service..."

    try {
        if ($Action -eq 'Disable') {
            Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
            $State.Service | Stop-Service -Force -ErrorAction Stop
            if (-not (Wait-ForServiceStatus -Service $State.Service -DesiredStatus 'Stopped')) {
                throw "Couldn't stop service with PowerShell"
            }
        } else {
            Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            $State.Service | Start-Service -ErrorAction Stop
            if (-not (Wait-ForServiceStatus -Service $State.Service -DesiredStatus 'Running')) {
                throw "Couldn't start service with PowerShell"
            }
        }
    }
    catch {
        Write-LogMessage "PowerShell command failed: $_. Trying CMD as fallback."
        $cmdAction = if ($Action -eq 'Disable') { 'stop' } else { 'start' }
        try {
            $null = & cmd /c sc $cmdAction $serviceName
            if ($LASTEXITCODE -ne 0) {
                throw "CMD command failed with exit code $LASTEXITCODE"
            }
        }
        catch {
            Write-LogMessage "Couldn't $Action the service using CMD fallback: $_"
            return $false
        }
    }
    finally {
        $State.Service.Refresh()
    }

    Write-LogMessage "Service ${Action}d successfully."
    return $true
}

# Main script
try {
    Write-LogMessage "Script started."
    Write-Host @"
This script toggles the NVIDIA Display Container LS service.
Disabling it will turn off the NVIDIA Control Panel.
Enabling it will turn on the NVIDIA Control Panel.
"@

    Wait-ForKeyPress "Press any key to continue..."

    Clear-Host
    Write-Host "Working on it..."

    $state = Get-NvidiaServiceState
    $action = if ($state.IsRunning -and $state.IsAutomatic) { 'Disable' } else { 'Enable' }

    $result = Set-NvidiaServiceState -Action $action -State $state

    if ($result) {
        Write-Host "All done! The service is now $($action)d."
    } else {
        Write-Host "Oops, something went wrong. Check the log file for more info."
    }
}
catch {
    Write-LogMessage "Unexpected error: $_"
    Write-Host "Unexpected error occurred. Check the log file for details."
}
finally {
    Wait-ForKeyPress "Press any key to exit..."
}
