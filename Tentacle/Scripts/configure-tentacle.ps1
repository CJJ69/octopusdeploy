[CmdletBinding()]
Param()

$Installer="Tentacle"
. ./common.ps1

$ServerApiKey = $env:ServerApiKey;
$ServerUsername = $env:ServerUsername;
$ServerPassword = $env:ServerPassword;
$ServerUrl = $env:ServerUrl;
$TargetEnvironment = $env:TargetEnvironment;
$TargetRole = $env:TargetRole;
$TargetWorkerPool = $env:TargetWorkerPool;
$TargetName=$env:TargetName;
$ListeningPort=$env:ListeningPort;
$PublicHostNameConfiguration=$env:PublicHostNameConfiguration;
$CustomPublicHostName=$env:CustomPublicHostName;
$InternalListeningPort=10933;
$ServerPort=$env:ServerPort;
$MachinePolicy = $env:MachinePolicy;
$ResetTrust=$env:ResetTrust;

$TentacleExe=$Exe
function Configure-Tentacle
{
  Write-Log "Configure Octopus Deploy Tentacle"

  if(!(Test-Path $TentacleExe)) {
    throw "File not found. Expected to find '$TentacleExe' to perform setup."
  }

  $thumbprint = .$TentacleExe @( 'show-thumbprint' )
  
  Write-Log "Setting directory paths ..."
  Execute-Command $TentacleExe @(
    'configure',
    '--console',
    '--instance', 'Tentacle',
    '--home', 'C:\TentacleHome',
    '--app', 'C:\Applications')

  Write-Log "Configuring communication type ..."
  if ($ServerPort -ne $null) {
    Execute-Command $TentacleExe @(
      'configure',
      '--console',
      '--instance', 'Tentacle',
      '--noListen', '"True"')
  } else {
    Execute-Command $TentacleExe @(
      'configure',
      '--console',
      '--instance', 'Tentacle',
      '--port', $InternalListeningPort,
      '--noListen', '"False"')
  }

  if ($ResetTrust) {
      if ("" -ne $thumbprint) {
          Write-Log "Existing thumbprint: $thumbprint attempt to Deregister ..."
          Deregister-Tentacle
      }
      
      Write-Log "Updating trust ..."
      Execute-Command $TentacleExe @(
        'configure',
        '--console',
        '--instance', 'Tentacle',
        '--reset-trust')
  }
  
  Write-Log "Creating certificate ..."
  Execute-Command $TentacleExe @(
    'new-certificate',
    '--console',
    '--instance', 'Tentacle',
    '--if-blank'
  )
}

# After the Tentacle is registered with Octopus, Tentacle listens on a TCP port, and Octopus connects to it. The Octopus server
# needs to know the public IP address to use to connect to this Tentacle instance. Is there a way in Windows Azure in which we can
# know the public IP/host name of the current 10?
function Get-MyPublicIPAddress
{
  Write-Verbose "Getting public IP address"

  try
  {
    $ip = Invoke-RestMethod -Uri https://api.ipify.org
  }
  catch
  {
    Write-Verbose $_
  }
  return $ip
}

function Get-PublicHostName
{
  param (
    [ValidateSet("PublicIp", "FQDN", "ComputerName", "Custom")]
    [string]$publicHostNameConfiguration = "PublicIp"
  )
  if ($publicHostNameConfiguration -eq "Custom")
  {
    $publicHostName = $customPublicHostName
  }
  elseif ($publicHostNameConfiguration -eq "FQDN")
  {
    $computer = Get-CimInstance win32_computersystem
    $domain = $computer.Domain
    $publicHostName = $computer.DNSHostName
	if ("WORKGROUP" -ne $domain) {
		$publicHostName += ".$domain"
	}
  }
  elseif ($publicHostNameConfiguration -eq "ComputerName")
  {
    $publicHostName = $env:COMPUTERNAME
  }
  else
  {
    $publicHostName = Get-MyPublicIPAddress
  }
  $publicHostName = $publicHostName.Trim()
  return $publicHostName
}

function Validate-Variables() {
  if($ServerApiKey -eq $null) {
    if($ServerPassword -eq $null -or $ServerUsername -eq $null){
      Write-Error "No 'ServerApiKey' or username/pasword environment variables are available"
      exit 1;
    }
  }

  if($ServerUrl -eq $null) {
    Write-Error "Missing 'ServerUrl' environment variable"
    exit 1;
  }

  if($TargetWorkerPool -ne $null) {
    if($TargetEnvironment -ne $null) {
      Write-Error "The 'TargetEnvironment' environment variable is not valid in combination with the 'TargetWorkerPool' variable"
      exit 1;
    }
    if($TargetRole -ne $null) {
      Write-Error "The 'TargetRole' environment variable is not valid in combination with the 'TargetWorkerPool' variable"
      exit 1;
    }
  } else {
    if($TargetEnvironment -eq $null) {
      Write-Error "Missing 'TargetEnvironment' environment variable"
      exit 1;
    }
    
    if($TargetRole -eq $null) {
      Write-Error "Missing 'TargetRole' environment variable"
      exit 1;
    }
  }

  if($PublicHostNameConfiguration -eq $null) {
    $script:PublicHostNameConfiguration = 'ComputerName'
  }

  Write-Log " - server endpoint '$ServerUrl'"
  Write-Log " - api key '##########'"
  if ($null -ne $ServerPort) {
    Write-Log " - communication mode 'Polling' (Active)"
    Write-Log " - server port $ServerPort"
  } else {
    Write-Log " - communication mode 'Listening' (Passive)"
    Write-Log " - registered port $ListeningPort"
  }
  if ($null -ne $TargetWorkerPool) {
    Write-Log " - worker pool '$TargetWorkerPool'"
  } else {
    Write-Log " - environment '$TargetEnvironment'"
    Write-Log " - role '$TargetRole'"
  }
  Write-Log " - host '$PublicHostNameConfiguration'"
  if($TargetName -ne $null) {
    Write-Log " - name '$env:TargetName'"
  }
}

function Restore-Configuration() {
  if (-not(Test-Path $TentacleConfig)) {
    # work around https://github.com/docker/docker/issues/20127
    Copy-item $TentacleConfigTemp $TentacleConfig
  }
}

function Register-Tentacle(){
 Write-Log "Registering with server ..."

  New-Variable -Name arg -Option AllScope
  if($TargetWorkerPool -ne $null) {
    $arg = @(
      'register-worker',
      '--console',
    '--instance', 'Tentacle',
    '--server', $ServerUrl,
    '--policy', $MachinePolicy,
    '--force')
  } else {
    $arg = @(
      'register-with',
      '--console',
    '--instance', 'Tentacle',
    '--server', $ServerUrl,
    '--policy', $MachinePolicy,
    '--force')
  }

  if ($null -ne $ServerPort) {
    $arg += "--comms-style"
    $arg += "TentacleActive"
    $arg += "--server-comms-port"
    $arg += $ServerPort
  } else {
    $arg += "--comms-style"
    $arg += "TentaclePassive"
    $publicHostName = Get-PublicHostName $PublicHostNameConfiguration;
    $arg += "--publicHostName"
    $arg += $publicHostName
    if (($null -ne $ListeningPort) -and ($ListeningPort -ne $InternalListeningPort)) {
      $arg += "--tentacle-comms-port"
      $arg += $ListeningPort
    }
  }

  if(!($ServerApiKey -eq $null)) {
    Write-Verbose "Registering Tentacle with api key"
    $arg += "--apiKey";
    $arg += $ServerApiKey
  } else {
    Write-Verbose "Registering Tentacle with username/password"
    $arg += "--username";
    $arg += $ServerUsername
    $arg += "--password";
    $arg += $ServerPassword
  }

  if($TargetName -ne $null) {
    $arg += "--name";
    $arg += $TargetName;
  }

  if($TargetEnvironment -ne $null) {
    $TargetEnvironment.Split(",") | ForEach {
      $arg += '--environment';
      $arg += $_.Trim();
     };
  }

  if($TargetRole -ne $null) {
     $TargetRole.Split(",") | ForEach {
      $arg += '--role';
      $arg += $_.Trim();
     };
  }

  if($TargetWorkerPool -ne $null) {
    $TargetWorkerPool.Split(",") | ForEach {
      $arg += '--workerpool';
      $arg += $_.Trim();
     };
  }

  # check if Octopus Server available and responding...
  $ServerResponse = Get-ServerResponseIsOK
  Write-Log "Check is server responding: $ServerResponse"
  Execute-Command $TentacleExe $arg;
}

function Deregister-Tentacle(){
 Write-Log "Deregistering with server ..."

  New-Variable -Name arg -Option AllScope
  if($TargetWorkerPool -ne $null) {
    $arg = @(
      'deregister-worker',
      '--console',
    '--instance', 'Tentacle',
    '--server', $ServerUrl,
    '--force')
  } else {
    $arg = @(
      'deregister-with',
      '--console',
    '--instance', 'Tentacle',
    '--server', $ServerUrl,
    '--force')
  }


  if(!($ServerApiKey -eq $null)) {
    Write-Verbose "Deregistering Tentacle with api key"
    $arg += "--apiKey";
    $arg += $ServerApiKey
  } else {
    Write-Verbose "Deregistering Tentacle with username/password"
    $arg += "--username";
    $arg += $ServerUsername
    $arg += "--password";
    $arg += $ServerPassword
  }

  # check if Octopus Server available and responding...
#  $ServerResponse = Get-ServerResponseIsOK
#  Write-Log "Check is server responding: $ServerResponse"
  Execute-Command $TentacleExe $arg;
}

function Get-ServerResponseIsOK() {
  # try to avoid tentacle registration timeout, wait longer for Octopus Server to become available to register...	
  $ServerCheckUrl = "$ServerUrl/api/octopusservernodes/ping"
  $Stoploop = $false
  [int]$RetryCount = 0
  [int]$Retries = 10
  [int]$RetryWaitSecs = 6
  $ServerStatus = ""

  Write-Verbose "Request response from $ServerCheckUrl"

  Do {
    $RetryCount = $RetryCount + 1
    Try {
      $response = Invoke-WebRequest $ServerCheckUrl -UseBasicParsing
      $ServerStatus = $response.StatusDescription
      if ($response.StatusCode -eq 200) {
        Write-Verbose "Server responding OK"
        $StopLoop = $true
      }
    } Catch {
      Write-Verbose $_
      $ServerStatus = "Error"
      If ($RetryCount -ge $Retries) {
        Write-Output "No response from server after $Retries retries."
        $StopLoop = $true
      } Else {
        Write-Verbose "Retry in $RetryWaitSecs."
        Start-Sleep -Seconds $RetryWaitSecs
      }
    }
  }
  While ($StopLoop -eq $false)
  return $ServerStatus
}

try
{
  Write-Log "==============================================="
  Write-Log "Configuring Octopus Deploy Tentacle"

  if(Test-Path c:\octopus-configuration.initstate){
    Write-Verbose "This Tentacle has already been initialized and registered so reconfiguration will be skipped";
    exit 0
  }

  Validate-Variables
  Write-Log "==============================================="

  #Restore-Configuration
  Configure-Tentacle
  Register-Tentacle
  "Configuration complete." | Set-Content "c:\octopus-configuration.initstate"

  Write-Log "Configuration successful."
  Write-Log ""
}
catch
{
  Write-Log $_
  exit 2
}
