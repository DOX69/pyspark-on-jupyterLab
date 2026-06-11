[CmdletBinding()]
param(
    [string]$SparkVersion = "4.1.2",
    [string]$SparkHome = "C:\spark",
    [string]$HadoopHome = "C:\hadoop",
    [switch]$ForceSparkReplace,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
    Write-Host ""
    Write-Host "=========================================================="
    Write-Host ">>> $Message"
    Write-Host "=========================================================="
}

$Workspace = $PSScriptRoot
$venvDir = Join-Path $Workspace ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

# 1. Check Python installation
Write-Step "Checking Python installation"
$pythonPath = Get-Command "python.exe" -ErrorAction SilentlyContinue
if (-not $pythonPath) {
    throw "Python is not installed or not in system PATH. Please install Python 3.10 or 3.11."
}

# 2. Handle Hadoop Helper Binaries (winutils.exe, hadoop.dll)
Write-Step "Handling Hadoop Helper Binaries (winutils.exe, hadoop.dll)"
$hadoopBin = Join-Path $HadoopHome "bin"
$winutils = Join-Path $hadoopBin "winutils.exe"
$hadoopDll = Join-Path $hadoopBin "hadoop.dll"

if (-not (Test-Path -LiteralPath $winutils) -or -not (Test-Path -LiteralPath $hadoopDll)) {
    Write-Host "Hadoop helper binaries missing from $hadoopBin. Downloading them..."
    if (-not (Test-Path -LiteralPath $hadoopBin)) {
        New-Item -ItemType Directory -Force -Path $hadoopBin | Out-Null
    }
    
    # Download winutils.exe and hadoop.dll from public archive
    $winutilsUrl = "https://raw.githubusercontent.com/cdarlint/winutils/master/hadoop-3.3.6/bin/winutils.exe"
    $hadoopDllUrl = "https://raw.githubusercontent.com/cdarlint/winutils/master/hadoop-3.3.6/bin/hadoop.dll"
    
    curl.exe -L --fail --output $winutils $winutilsUrl
    if ($LASTEXITCODE -ne 0) { throw "Failed to download winutils.exe" }
    
    curl.exe -L --fail --output $hadoopDll $hadoopDllUrl
    if ($LASTEXITCODE -ne 0) { throw "Failed to download hadoop.dll" }
    
    Write-Host "Hadoop helper binaries successfully downloaded to $hadoopBin"
} else {
    Write-Host "Hadoop helper binaries already present at $hadoopBin"
}

# 3. Run the skill installer script to bootstrap Spark, Java, and env variables
Write-Step "Running Spark and environment installer script"
$skillInstaller = Join-Path $Workspace ".agent\skills\install-spark-jupyterlab\scripts\install-spark-jupyterlab.ps1"
if (-not (Test-Path -LiteralPath $skillInstaller)) {
    throw "Skill installer not found at $skillInstaller. Please ensure the .agent/skills/install-spark-jupyterlab folder is present."
}

$installerArgs = @{
    SparkVersion = $SparkVersion
    SparkHome = $SparkHome
    HadoopHome = $HadoopHome
    Workspace = $Workspace
}
if ($ForceSparkReplace) { $installerArgs["ForceSparkReplace"] = $true }
if ($CheckOnly) { $installerArgs["CheckOnly"] = $true }

& $skillInstaller @installerArgs
if ($LASTEXITCODE -ne 0) {
    throw "Spark installer script failed."
}

if ($CheckOnly) {
    Write-Host "CheckOnly complete. Exiting."
    exit 0
}

# 4. Install requirements from requirements.txt to configure Jupyter extensions
Write-Step "Installing Python dependencies from requirements.txt"
& $venvPython -m pip install -r (Join-Path $Workspace "requirements.txt")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install Python requirements."
}

# 4b. Install jupyterlab-sparksql with --no-deps to bypass conflicting pins
Write-Step "Installing jupyterlab-sparksql with --no-deps"
& $venvPython -m pip install --no-deps jupyterlab-sparksql
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install jupyterlab-sparksql."
}

# 5. Configure IPython kernel extensions for SparkMonitor and SparkSQL
Write-Step "Configuring IPython kernel extensions for SparkMonitor and SparkSQL"
$ipythonConfig = Join-Path $HOME ".ipython\profile_default\ipython_kernel_config.py"
$ipythonConfigDir = Split-Path -Parent $ipythonConfig
if (-not (Test-Path -LiteralPath $ipythonConfigDir)) {
    New-Item -ItemType Directory -Force -Path $ipythonConfigDir | Out-Null
}
if (-not (Test-Path -LiteralPath $ipythonConfig)) {
    "c = get_config()  #noqa" | Set-Content -LiteralPath $ipythonConfig -Encoding UTF8
}

$bytes = [IO.File]::ReadAllBytes($ipythonConfig)
if (($bytes | Where-Object { $_ -eq 0 }).Count -gt 0) {
    Write-Warning "IPython config contains NUL bytes. Overwriting with clean file."
    "c = get_config()  #noqa" | Set-Content -LiteralPath $ipythonConfig -Encoding UTF8
}

$configLines = Get-Content -LiteralPath $ipythonConfig
$extensions = @(
    "c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')",
    "c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')"
)

foreach ($line in $extensions) {
    $activeMatch = $configLines | Where-Object { $_ -eq $line -and $_ -notmatch "^\s*#" }
    if (-not $activeMatch) {
        Add-Content -LiteralPath $ipythonConfig -Value $line -Encoding UTF8
        Write-Host "Configured IPython autoload: $line"
    }
}

Write-Step "Setup complete!"
Write-Host "To start JupyterLab, run: .\start-jupyter-lab.cmd"
Write-Host "To test PySpark, run: .\test-pyspark.cmd"
