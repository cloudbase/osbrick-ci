Param(
    [Parameter(Mandatory=$true)][string]$devstackIP,
    [string]$branchName='master',
    [string]$buildFor='openstack/os-brick',
    [string]$jobType='iscsi',
    [string]$isDebug='no',
    [string]$zuulChange=''
)

if ($isDebug -eq  'yes') {
    Write-Host "Debug info:"
    Write-Host "devstackIP: $devstackIP"
    Write-Host "branchName: $branchName"
    Write-Host "buildFor: $buildFor"
}

$projectName = $buildFor.split('/')[-1]

$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"
. "$scriptLocation\utils.ps1"
. "$scriptLocation\mpio_utils.ps1"

$hasProject = Test-Path $buildDir\$projectName
$hasNeutronTemplate = Test-Path $neutronTemplate
$hasNovaTemplate = Test-Path $novaTemplate
$hasConfigDir = Test-Path $configDir
$hasBinDir = Test-Path $binDir
$hasMkisoFs = Test-Path $binDir\mkisofs.exe
$hasQemuImg = Test-Path $binDir\qemu-img.exe
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($hasQemuImg) {
    $hasOldQemuImg = $(& $binDir\qemu-img.exe --version | sls "qemu-img version 1.2.0").Matches.Success
}

if ($jobType -eq 'fc' -and (! $(mpio_configured) )) {
    write-host "WARN: MPIO is not configured to claim FC disks on this node."
    write-host "Configuring MPIO, supressing reboot."
    configure_mpio
}

$pip_conf_content = @"
[global]
index-url = http://10.20.1.8:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.20.1.8
"@

$ErrorActionPreference = "SilentlyContinue"

# Do a selective teardown
Write-Host "Ensuring nova and neutron services are stopped."
Stop-Service -Name nova-compute -Force
Stop-Service -Name neutron-hyperv-agent -Force
Stop-Service -Name cinder-volume -Force

Write-Host "Stopping any possible python processes left."
Stop-Process -Name python -Force

if (Get-Process -Name nova-compute){
    Throw "Nova is still running on this host"
}

if (Get-Process -Name neutron-hyperv-agent){
    Throw "Neutron is still running on this host"
}

if (Get-Process -Name python){
    Throw "Python processes still running on this host"
}

$ErrorActionPreference = "Stop"

if (-not (Get-Service neutron-hyperv-agent -ErrorAction SilentlyContinue))
{
    Throw "Neutron Hyper-V Agent Service not registered"
}

if (-not (get-service nova-compute -ErrorAction SilentlyContinue))
{
    Throw "Nova Compute Service not registered"
}

if (-not (get-service cinder-volume -ErrorAction SilentlyContinue))
{
    Throw "Cinder Volume Service not registered"
}

if ($(Get-Service nova-compute).Status -ne "Stopped"){
    Throw "Nova service is still running"
}

if ($(Get-Service neutron-hyperv-agent).Status -ne "Stopped"){
    Throw "Neutron service is still running"
}

if ($(Get-Service cinder-volume).Status -ne "Stopped"){
    Throw "Cinder service is still running"
}

Write-Host "Cleaning up the config folder."
if ($hasConfigDir -eq $false) {
    mkdir $configDir
}else{
    Try
    {
        Remove-Item -Recurse -Force $configDir\*
    }
    Catch
    {
        Throw "Can not clean the config folder"
    }
}

if ($hasProject -eq $false){
    Get-ChildItem $buildDir
    Get-ChildItem ( Get-Item $buildDir ).Parent.FullName
    Throw "$projectName repository was not found. Please run gerrit-git-prep.sh for this project first"
}

if ($hasBinDir -eq $false){
    mkdir $binDir
}

if (($hasMkisoFs -eq $false) -or ($hasQemuImg -eq $false) -or ($hasOldQemuImg -eq $true)){
    Cmd /C "rmdir /S /Q $binDir\*"
    Invoke-WebRequest -Uri "http://10.20.1.14:8080/openstack_bin.zip" -OutFile "$bindir\openstack_bin.zip"
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$bindir\openstack_bin.zip", "$bindir")
    Remove-Item -Force "$bindir\openstack_bin.zip"
}

if ($hasNovaTemplate -eq $false){
    Throw "Nova template not found"
}

if ($hasNeutronTemplate -eq $false){
    Throw "Neutron template not found"
}

if ($isDebug -eq  'yes') {
    Write-Host "Status of $buildDir before GitClonePull"
    Get-ChildItem $buildDir
}

git config --global user.email "hyper-v_ci@microsoft.com"
git config --global user.name "Hyper-V CI"

ExecRetry {
    GitClonePull "$buildDir\nova" "https://git.openstack.org/openstack/nova.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\neutron" "https://git.openstack.org/openstack/neutron.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\networking-hyperv" "https://git.openstack.org/openstack/networking-hyperv.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\requirements" "https://git.openstack.org/openstack/requirements.git" $branchName
}
Get-ChildItem $buildDir

if ($jobType -eq 'smbfs')
{
    ExecRetry {
        GitClonePull "$buildDir\cinder" "https://git.openstack.org/openstack/cinder.git" $branchName
    }    
}

$hasLogDir = Test-Path $openstackLogs
if ($hasLogDir -eq $false){
    mkdir $openstackLogs
}

if (Test-Path $pythonArchive)
{
    Remove-Item -Force $pythonArchive
}
Invoke-WebRequest -Uri http://10.20.1.14:8080/python.zip -OutFile $pythonArchive
if (Test-Path $pythonDir)
{
    Cmd /C "rmdir /S /Q $pythonDir"
}
Write-Host "Ensure Python folder is up to date"
Write-Host "Extracting archive.."
[System.IO.Compression.ZipFile]::ExtractToDirectory("C:\$pythonArchive", "C:\")

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

$ErrorActionPreference = "SilentlyContinue"

& easy_install -U pip
& pip install -U setuptools
& pip install -U virtualenv
& pip install -U distribute
& pip install -U --pre pymi
& pip install cffi
& pip install numpy
& pip install pycrypto
& pip install -U os-win
& pip install amqp==1.4.9
& pip install pymysql
& pip install mysqlclient

$ErrorActionPreference = "Stop"

popd

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

cp $templateDir\distutils.cfg "$pythonDir\Lib\distutils\distutils.cfg"


if ($isDebug -eq  'yes') {
    Write-Host "BuildDir is: $buildDir"
    Write-Host "ProjectName is: $projectName"
    Write-Host "Listing $buildDir parent directory:"
    Get-ChildItem ( Get-Item $buildDir ).Parent.FullName
    Write-Host "Listing $buildDir before install"
    Get-ChildItem $buildDir
}

ExecRetry {
    pushd "$buildDir\requirements"
    Write-Host "Installing OpenStack/Requirements..."
    & pip install -c upper-constraints.txt -U pbr virtualenv httplib2 prettytable>=0.7 setuptools
    & pip install -c upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install openstack/requirements from repo" }
    popd
}

ExecRetry {
    if ($isDebug -eq  'yes') {
        Write-Host "Content of $buildDir\neutron"
        Get-ChildItem $buildDir\neutron
    }
    pushd $buildDir\neutron
    Write-Host "Installing openstack/neutron..."
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install neutron from repo" }
    popd
}

ExecRetry {
    if ($isDebug -eq  'yes') {
        Write-Host "Content of $buildDir\networking-hyperv"
        Get-ChildItem $buildDir\networking-hyperv
    }
    pushd $buildDir\networking-hyperv
    Write-Host "Installing openstack/networking-hyperv..."
    & update-requirements.exe --source $buildDir\requirements .
    if (($branchName -eq 'stable/liberty') -or ($branchName -eq 'stable/mitaka')) {
        & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    } else {
        & pip install -e $buildDir\networking-hyperv
    }
    if ($LastExitCode) { Throw "Failed to install networking-hyperv from repo" }
    popd
}

if($jobType -eq 'smbfs')
{
    ExecRetry {
        if ($isDebug -eq  'yes') {
            Write-Host "Content of $buildDir\cinder"
            Get-ChildItem $buildDir\cinder
        }
        pushd $buildDir\cinder

        git remote add downstream https://github.com/petrutlucian94/cinder
        
        ExecRetry {
            git fetch downstream
            if ($LastExitCode) { Throw "Failed fetching remote downstream petrutlucian94" }
        }

        git checkout -b "testBranch"
        if ($branchName.ToLower() -eq "master") {
            cherry_pick dcd839978ca8995cada8a62a5f19d21eaeb399df
            cherry_pick f711195367ead9a2592402965eb7c7a73baebc9f
        }
        else {
            cherry_pick 0c13ba732eb5b44e90a062a1783b29f2718f3da8
            cherry_pick 06ee0b259daf13e8c0028a149b3882f1e3373ae1
        }
        Write-Host "Installing openstack/cinder..."
        & update-requirements.exe --source $buildDir\requirements .
        & pip install -c $buildDir\requirements\upper-constraints.txt -U .
        if ($LastExitCode) { Throw "Failed to install cinder from repo" }
        popd
    }
}

ExecRetry {
    pushd $buildDir\os-brick
    Write-Host "Installing openstack/os-brick..."
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    popd
}


ExecRetry {
    if ($isDebug -eq  'yes') {
        Write-Host "Content of $buildDir\nova"
        Get-ChildItem $buildDir\nova
    }
    pushd $buildDir\nova

    Write-Host "Installing openstack/nova..."
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -c $buildDir\requirements\upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install nova fom repo" }
    popd
}

# Note: be careful as WMI queries may return only one element, in which case we
# won't get an array. To make it easier, we can just make sure we always have an
# array.
$cpu_array = ([array](gwmi -class Win32_Processor))
$cores_count = $cpu_array.count * $cpu_array[0].NumberOfCores
$novaConfig = (gc "$templateDir\nova.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser)
$neutronConfig = (gc "$templateDir\neutron_hyperv_agent.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser).replace('[CORES_COUNT]', "$cores_count")

Set-Content $configDir\nova.conf $novaConfig
if ($? -eq $false){
    Throw "Error writting $configDir\nova.conf"
}

Set-Content $configDir\neutron_hyperv_agent.conf $neutronConfig
if ($? -eq $false){
    Throw "Error writting $configDir\neutron_hyperv_agent.conf"
}

cp "$templateDir\policy.json" "$configDir\"
cp "$templateDir\interfaces.template" "$configDir\"

if ($jobType -eq 'smbfs')
{
    & $scriptLocation\generateCinderCfg.ps1 $configDir $cinderTemplate $devstackIP $rabbitUser $openstackLogs $lockPath
}

$hasNovaExec = Test-Path "$pythonScripts\nova-compute.exe"
if ($hasNovaExec -eq $false){
    Throw "No nova-compute.exe found"
}

$hasNeutronExec = Test-Path "$pythonScripts\neutron-hyperv-agent.exe"
if ($hasNeutronExec -eq $false){
    Throw "No neutron-hyperv-agent.exe found"
}


Write-Host "Done buildiing env"
