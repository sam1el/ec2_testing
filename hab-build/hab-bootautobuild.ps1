# Configures and executes Habitat plan build on a temporary Windows system

# Set Variables for later usage
$buildlocation = "C:\temp\hab_effortless"
$origin = "gio"
$pkgversion = Get-Content "C:\temp\pkgversion"
$authtoken = Get-Content "C:\temp\authtoken"
$gitcommit = Get-Content "C:\temp\gitcommit"
$bldrurl = "http://bldrserver"
$repourl = "https://bitbucket.git"
$env:HAB_LICENSE = "accept"
$env:HAB_ORIGIN = "$origin"
$env:HAB_AUTH_TOKEN = "$authtoken"
$env:HAB_BLDR_URL = "$bldrurl"
$env:HAB_GITCOMMIT = $gitcommit
$env:HAB_PKGVERSION = $pkgversion
# $env:HAB_FEAT_EVENT_STREAM = "1"
# $env:RUST_LOG = "debug"
# $env:RUST_BACKTRACE = 1

# Install Habitat if not present on system
If (Test-Path -Path 'C:\habitat\') {'Nothing to do'} Else {
    Set-ExecutionPolicy Bypass -Scope Process -Force;
    invoke-webrequest -uri 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1' -outfile habinstall.ps1
    .\habinstall.ps1 -v 1.5.50
}
# Clone the Git repository if not running locally in Vagrant or if the repo path otherwise does not exist.
If (Test-Path -Path "$buildlocation") {'Nothing to do'} Else {
    hab license accept
    hab pkg install core/git
    Set-Location 'c:\temp'
    hab pkg exec core/git git clone -q "https://gitrepo"
    Set-Location $buildlocation
    hab pkg exec core/git git checkout $gitcommit
}

Write-Output "Building with $env:HAB_PKGVERSION"

# Configure Habitat and Build Package
Set-Location "$buildlocation"
hab license accept
hab origin key download aig 20190805204456
hab origin key download aig 20190805204456 -s
hab pkg install core/hab-studio
hab studio build habitat

# Validate that build succeeded
Test-Path -Path "$buildlocation\results\last_build.ps1"
if ($?) {
  Write-host 'Build successful, proceeding.'
}
else {
  Write-Error 'Build failed, did not proceed to upload' -ErrorAction stop
}

# Source the build file
. $buildlocation\results\last_build.ps1

# Upload to Habitat Builder
hab pkg upload $buildlocation\results\$pkg_artifact -u $bldrurl --channel test
