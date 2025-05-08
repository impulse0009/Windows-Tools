#Requires -RunAsAdministrator

<#!
Quick Rundown;
//
    Problem?
        Troublesome CPU spikes caused by services while gaming >:(
    Solution!
        Band-Aid the situation by Disabling the services :D
//
What is covered;
    Services.
        "NVDisplay.ContainerLocalSystem"
        "NvContainerLocalSystem"
    Functions.
        Nvidia Control Panel
        Nvidia App
        Other Nvidia-ey things for GPU, Windows, Display, etc
//
What this does;
    Script.
        Toggle service running states to opposite state (Enable or Disable)
    Disclaimer.
        DOES NOT affect startup states
        ONLY toggles active running states on + off when run
//
Future Revisions;
    Brevity.
        functions
        variables
        comments
        console text output
        logs
        others?
    Include More?
        services/ modules/ backend supplementary apps
        others?
    Layout.
        background + text color formatting?
        custom arguments/parameters for granularity?
        better defined variables!!!
        rearange and find better ways to compartmentalize by type
        prevent errors
        error checking
    Permissions.
        not brute force/ required perms only
#>

# Service names and log location
$serviceNames = @(
    'NVDisplay.ContainerLocalSystem',
    'NvContainerLocalSystem'
)
$logFile = "$PSScriptRoot\toggle-nvidia-services.log"

# Get date and time for log file entries
function Write-LogMessage {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts - $Message" | Add-Content -Path $logFile -Force
}

function Wait-ForKeyPress {
    param([string]$Prompt)
    Write-Host $Prompt
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Get-NvidiaServiceState {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        return @{ Name = $Name; Service = $svc; IsRunning = ($svc.Status -eq 'Running'); IsAutomatic = ($svc.StartType -eq 'Automatic') }
    }
    catch {
        Write-LogMessage "Error: Couldn't find the $Name service."
        throw
    }
}

function Wait-ForServiceStatus {
    param(
        [System.ServiceProcess.ServiceController]$Service,
        [string]$DesiredStatus,
        [int]$TimeoutSeconds = 5
    )
    try {
        $Service.WaitForStatus($DesiredStatus, [TimeSpan]::FromSeconds($TimeoutSeconds))
        return $true
    }
    catch {
        Write-LogMessage "Service $($Service.Name) didn't reach $DesiredStatus within $TimeoutSeconds seconds."
        return $false
    }
}

function Set-NvidiaServiceState {
    param(
        [string]$Name,
        [ValidateSet('Enable','Disable')][string]$Action,
        [hashtable]$State
    )
    Write-LogMessage "Trying to $Action the $Name service..."
    try {
        if ($Action -eq 'Disable') {
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
            $State.Service | Stop-Service -Force -ErrorAction Stop
            if (-not (Wait-ForServiceStatus -Service $State.Service -DesiredStatus 'Stopped')) { throw "Couldn't stop service with PowerShell" }
        } else {
            Set-Service -Name $Name -StartupType Automatic -ErrorAction Stop
            $State.Service | Start-Service -ErrorAction Stop
            if (-not (Wait-ForServiceStatus -Service $State.Service -DesiredStatus 'Running')) { throw "Couldn't start service with PowerShell" }
        }
    }
    catch {
        Write-LogMessage "PowerShell command failed: $_. Trying CMD as fallback."
        $cmdAction = if ($Action -eq 'Disable') { 'stop' } else { 'start' }
        try {
            $null = & cmd /c sc $cmdAction $Name
            if ($LASTEXITCODE -ne 0) { throw "CMD command failed with exit code $LASTEXITCODE" }
        }
        catch {
            Write-LogMessage "Couldn't $Action the service using CMD fallback: $_"
            return $false
        }
    }
    finally { $State.Service.Refresh() | Out-Null }
    Write-LogMessage "Service $Name ${Action}d successfully."
    return $true
}

# --- main ----------------------------------------------------------------
try {
    Write-LogMessage 'Script started.'

    # Console intro with dynamic current running state for both services
    Write-Host 'Toggle these NVIDIA background services together:'
    Write-Host ''
    foreach ($name in $serviceNames) {
        $st = Get-NvidiaServiceState -Name $name
        $stateText = if ($st.IsRunning) { 'Enabled' } else { 'Disabled' }
        Write-Host "$($st.Name) - Is Currently $stateText"
    }
    Write-Host ''
    Write-Host 'Disable= You CANNOT use Nvidia Control Panel + Nvidia App >:('
    Write-Host ''
    Write-Host 'Enable= You CAN use Nvidia Control Panel + Nvidia App :)'
    Write-Host ''
    Wait-ForKeyPress 'Press any key to continue...'
    Clear-Host
    Write-Host 'Toggling Running States...'

    # Toggle running state of both services 
    # Enabled goes to Disabled
    # Disabled goes to Enabled
    $firstState = Get-NvidiaServiceState -Name $serviceNames[0]
    $action = if ($firstState.IsRunning -and $firstState.IsAutomatic) { 'Disable' } else { 'Enable' }

    $allOk = $true
    foreach ($svcName in $serviceNames) {
        $state = Get-NvidiaServiceState -Name $svcName
        if (-not (Set-NvidiaServiceState -Name $svcName -Action $action -State $state)) { $allOk = $false; break }
    }

    if ($allOk) { Write-Host "All done! Services are now $action`d." } 
    else       { Write-Host 'Oops, something went wrong. Check the log, located next to script file location, for details.' -ForegroundColor Red }
}
catch {
    Write-LogMessage "Unexpected error: $_"
    Write-Host 'Unexpected error >:( occurred. Check the log file for details.' -ForegroundColor Red
}
finally {
    Wait-ForKeyPress 'Press any key to exit...'
}
