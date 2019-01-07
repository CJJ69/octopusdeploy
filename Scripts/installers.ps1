
function Stage-Installer {	
  Write-Log "Install path $installBasePath"
  if (Test-Path $installBasePath) {
    Write-Log "Install path exists!"
  } else {
    Write-Log "Creating installation folder at '$installBasePath' ..."
    New-Item -ItemType Directory -Path $installBasePath | Out-Null
  }

	if($env:DownloadUrl -ne $null){
    $DownloadUrl = $env:DownloadUrl
		Write-Log "Explicit download url provided"
	} elseif($Version -eq $null) {
    $DownloadUrl = $DownloadUrlLatest
		Write-Log "No version specified for install. Using location of latest.";    
	} elseif($Version -eq "latest") {
    $DownloadUrl = $DownloadUrlLatest
    Write-Log "latest version specified for install. Using location of latest.";    
	} else {
		$DownloadUrl = $DownloadBaseUrl + $MsiFileName
  }
  
  # Only download again if missing; can COPY from local to reduce download/build time
  if (Test-Path $MsiPath) {
    Write-Log "Installer exists!"
  } else {
    Write-Log "Downloading installer '$downloadUrl' to '$MsiPath' ..."
    (New-Object Net.WebClient).DownloadFile($downloadUrl, $MsiPath)
      Write-Log "done."
  }
}

function Install-OctopusDeploy
{
  $MsiLogPath = $MsiPath + '.log'
  Write-Log "Installing $MsiFileName"
  Write-Log "Starting MSI Installer"
  $MsiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $MsiPath /qn /l*v $MsiLogPath" -Wait -Passthru).ExitCode
  Write-Log "MSI installer returned exit code $MsiExitCode"
  if ($MsiExitCode -ne 0) {
    Write-Log "-------------"
    Write-Log "MSI Log file:"
    Write-Log "-------------"
    Get-Content $MsiLogPath
    Write-Log "-------------"
    throw "Install of $MsiFileName failed, MSIEXEC exited with code: $msiExitCode. View the log at $MsiLogPath"
  }
}

function Delete-InstallLocation
{
  Write-Log "Delete Install Location"
  if (-not (Test-Path $InstallBasePath))
  {
    Write-Log "Install location didn't exist - skipping delete"
  }
  else
  {
    Get-ChildItem $InstallBasePath -Recurse | Remove-Item -Force
    Remove-Item $InstallBasePath -Recurse -Force
  }
}
