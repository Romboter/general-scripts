# This script is designed to install or update the Twingate Windows client application.
# It can be run locally as a scheduled task, or pushed remotely via a tool like Intune.

# The script has a couple of optional features:
# - It can first uninstall the client app before re-installing it from scratch
# - It can install a machinekey.conf to enforce always-on connectivity (mostly for Twingate Internet Security)
# - It can create a scheduled task to auto-start the Twingate client application if it's ever quit by the user

# By default the script will always check to see if the Twingate client application is running, and kill it.  It will
# also check to see if the .NET Desktop Runtime 6.0 is installed, and install it if it is not.

###################################
##  Configure Optional Features  ##
###################################

# To uninstall the client app before re-installing, set to true
$uninstallFirst = $false

# To create a machinekey.conf file, set $createMachineKey to true, and paste the contents of the file in the $machineKey variable.
# The machinekey.conf contents are found in your Twingate Admin Console, under the Internet Security section.
# When you go to Client Configuration you can create a new machine key, and copy the contents to paste in the variable below.
# Ex:
# $machineKeyContent = @'
# {
#   "version": "2",
#   "network": "test.twingate.com",
#   "private_key": "-----BEGIN PRIVATE KEY-----\PRIVATEKEYGOESHERE\n-----END PRIVATE KEY-----",
#   "id": "IDGOESHERE"
# }
# '@
#
# Make sure to paste the contents of the machinekey.conf file such that it matches the format above.

$createMachineKey = $false
$machineKeyTargetFolder = "C:\ProgramData\Twingate" # Don't touch this
$machineKeyContent = @"
machinekey
"@

# To create a scheduled task to auto-start the Twingate client application if it's ever quit by the user, set to true
# You can also choose how often to check if the Twingate client is running, and how often to restart it.
$createScheduledTask = $false
$taskName = "Twingate Client Restart"
$taskDescription = "This task will check every 5 minutes to see if the Twingate client is running, and restart it if it is not."
$taskMinutes = 5

###################################
##         Set Variables         ##
###################################

# Twingate network name, ie networkname.twingate.com when you log in to the Admin Console
# It's important to change this to your network name if you want to auto-populate it.
# If you are installing a machinekey.conf then that will override this.
$twingateNetworkName = "networkname" 

# Path to the Twingate client executable post-installation
$twingateClientPath = "C:\Program Files\Twingate\Twingate.exe"

# Twingate Windows service name
$twingateServiceName = "twingate.service"



# Check to see if Twingate is already running, if so kill it
Write-Host [+] Checking for existing Twingate install
if ((Get-Process -Name "Twingate" -ErrorAction SilentlyContinue) -And (Get-Service -Name $twingateServiceName -ErrorAction SilentlyContinue)) {
	Stop-Service -Name $twingateServiceName -Force -ErrorAction SilentlyContinue
	Stop-Process -Name "Twingate" -Force -ErrorAction SilentlyContinue
}

# If the uninstallFirst variable is set to true, then uninstall the Twingate client
# This is useful if you want to ensure a clean install

if ($uninstallFirst) {
    Write-Host [+] Uninstall flag set, uninstalling Twingate Client application
    $twingateApp = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name.Contains("Twingate")}
    if ($twingateApp) {
        $twingateApp.Uninstall()
    }
}

# Check to see if the .NET Desktop Runtime 6.0 is already installed
Write-Host [+] Checking if .NET Desktop Runtime 6.0 is already installed
$dotnetRuntime = Get-WmiObject -Query "SELECT * FROM Win32_Product WHERE Name LIKE '%.NET%Runtime%6.%.%'"
if ($dotnetRuntime -ne $null) {
    Write-Host [+] .NET Desktop Runtime 6.0 is already installed
} else {
    # Installing the .NET Desktop Runtime
    Write-Host [+] .NET Desktop Runtime 6.0 is not installed
    Write-Host [+] Downloading .NET Desktop Runtime
    $AgentURI = 'https://download.visualstudio.microsoft.com/download/pr/a1da19dc-d781-4981-84e9-ffa0c05e00e9/46f3cd2015c27a0e93d7c102a711577e/windowsdesktop-runtime-6.0.31-win-x64.exe'
    $AgentDest = 'C:\Windows\Temp\windowsdesktop-runtime-6.0.31-win-x64.exe'
    Invoke-WebRequest $AgentURI -OutFile $AgentDest -UseBasicParsing
    Write-Host [+] Installing the .NET Desktop Runtime
    cmd /c "C:\Windows\Temp\windowsdesktop-runtime-6.0.31-win-x64.exe /install /quiet /norestart"
    Write-Host [+] Finished installing .NET Desktop Runtime
}

# Installing the Twingate Client
Write-Host [+] Downloading Twingate Client
$AgentURI = 'https://api.twingate.com/download/windows?installer=msi'
$AgentDest = 'C:\Windows\Temp\TwingateInstaller.msi'
Invoke-WebRequest $AgentURI -OutFile $AgentDest -UseBasicParsing
Write-Host [+] Installing the Twingate Client
cmd /c "msiexec.exe /i C:\Windows\Temp\TwingateInstaller.msi /qn network=$twingateNetworkName.twingate.com no_optional_updates=true"
Write-Host [+] Finished installing Twingate Client
Write-Host [+] Starting Twingate Client

# If the createMachineKey variable is set to true, then create the machinekey.conf file
if ($createMachineKey) {
    Write-Host [+] Machinekey.conf flag set, creating machinekey.conf
    Write-Host [+] Checking for target machinekey.conf folder
    if (-not (Test-Path $machineKeyTargetFolder)) {
        Write-Host [+] Creating Twingate folder
        New-Item -ItemType Directory -Path $machineKeyTargetFolder
    }
    Write-Host [+] Creating machinekey.conf
    New-Item "$machineKeyTargetFolder\machinekey.conf" -ItemType File -Value $machineKeyContent
    Write-Host [+] Finished installing machinekey.conf
}

# If the createScheduledTask variable is set to true, then create the scheduled task
if ($createScheduledTask) {
    Write-Host [+] Scheduled Task flag set, creating scheduled task
    Write-Host [+] Creating scheduled task
    $action = New-ScheduledTaskAction -Execute $twingateClientPath
    $taskTrigger = @(
        $(New-ScheduledTaskTrigger -Once -At 12:01AM -RepetitionInterval (New-TimeSpan -Minutes $taskMinutes)),
        $(New-ScheduledTaskTrigger -Daily -At 12:01AM),
        $(New-ScheduledTaskTrigger -AtStartup)
    )
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $taskTrigger -Settings $taskSettings
    Write-Host [+] Finished creating scheduled task

    # Since a scheduled task has been created, start it and the Twingate service
    Write-Host [+] Starting Task
    Start-ScheduledTask -TaskName $taskName
    Start-Service -Name $twingateServiceName -ErrorAction SilentlyContinue
} else {
    Write-Host [+] Scheduled Task flag not set, skipping scheduled task creation

    # Start the Twingate service and application
    Start-Process -FilePath $twingateClientPath
    Start-Service -Name $twingateServiceName -ErrorAction SilentlyContinue
}

Write-Host [+] Finished running Twingate Client installer script