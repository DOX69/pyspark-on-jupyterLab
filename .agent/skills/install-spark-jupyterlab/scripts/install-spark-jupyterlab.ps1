[CmdletBinding()]
param(
  [string]$SparkVersion = "latest",
  [string]$SparkHome = "C:\spark",
  [string]$HadoopHome = "",
  [string]$Workspace = (Join-Path $HOME "jupyter-lab"),
  [string]$WinutilsBinSource = "",
  [switch]$CheckOnly,
  [switch]$ForceSparkReplace
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
  Write-Host ""
  Write-Host "==> $Message"
}

function Get-CommandPath($Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Get-JavaMajorVersion {
  $java = Get-CommandPath "java.exe"
  if (-not $java) { return $null }
  $text = (& java --version 2>&1 | Out-String)
  if ($text -match 'openjdk\s+(\d+)') { return [int]$Matches[1] }
  if ($text -match 'java\s+version\s+"(\d+)') { return [int]$Matches[1] }
  return $null
}

function Get-PythonLauncher {
  if ($env:pythonLocation) {
    $pythonFromAction = Join-Path $env:pythonLocation "python.exe"
    if (Test-PythonVersion $pythonFromAction @()) {
      return @{ Command = $pythonFromAction; Args = @() }
    }
  }

  $python = Get-CommandPath "python.exe"
  if ($python -and (Test-PythonVersion $python @())) {
    return @{ Command = $python; Args = @() }
  }

  $candidates = @("3.11", "3.10")
  foreach ($version in $candidates) {
    if (Test-PythonVersion "py" @("-$version")) {
      return @{ Command = "py"; Args = @("-$version") }
    }
  }

  return $null
}

function Test-PythonVersion($Command, [string[]]$PythonArgs) {
  try {
    $versionText = (& $Command @($PythonArgs + @("--version")) 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $versionText -notmatch 'Python\s+3\.(10|11)\.') { return $false }
    & $Command @($PythonArgs + @("-c", "import ensurepip, venv")) *> $null
    if ($LASTEXITCODE -eq 0) { return $true }
  } catch {}
  return $false
}

function Invoke-NativeCommand($FilePath, [string[]]$Arguments, $FailureMessage) {
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FailureMessage (exit code $LASTEXITCODE)"
  }
}

function Invoke-Python($Launcher, [string[]]$PythonArgs, $FailureMessage) {
  & $Launcher.Command @($Launcher.Args + $PythonArgs)
  if ($LASTEXITCODE -ne 0) {
    throw "$FailureMessage (exit code $LASTEXITCODE)"
  }
}

function Ensure-Directory($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Set-UserEnvironment($Name, $Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, [EnvironmentVariableTarget]::User)
  Set-Item -Path "Env:$Name" -Value $Value
}

function Add-UserPathEntry($Entry) {
  $target = [EnvironmentVariableTarget]::User
  $path = [Environment]::GetEnvironmentVariable("Path", $target)
  if ($null -eq $path) { $path = "" }
  $entries = $path -split ';' | Where-Object { $_ -ne "" }
  if (-not ($entries | Where-Object { $_.TrimEnd('\') -ieq $Entry.TrimEnd('\') })) {
    $entries += $Entry
    [Environment]::SetEnvironmentVariable("Path", ($entries -join ';'), $target)
  }
}

function Download-File($Url, $OutFile) {
  Ensure-Directory (Split-Path -Parent $OutFile)
  Invoke-NativeCommand "curl.exe" @("-L", "--fail", "--output", $OutFile, $Url) "Download failed: $Url"
}

function Verify-Sha512($File, $ShaUrl) {
  $shaFile = "$File.sha512"
  Download-File $ShaUrl $shaFile
  $expected = ((Get-Content -LiteralPath $shaFile -Raw) -split '\s+')[0].ToUpperInvariant()
  $actual = (Get-FileHash -Algorithm SHA512 -LiteralPath $File).Hash.ToUpperInvariant()
  if ($expected -ne $actual) { throw "SHA-512 checksum mismatch for $File" }
}

function Resolve-SparkVersion($RequestedVersion) {
  if ($RequestedVersion -ne "latest") { return $RequestedVersion }
  try {
    $listing = (Invoke-WebRequest -UseBasicParsing -Uri "https://downloads.apache.org/spark/" -TimeoutSec 30).Content
    $versions = [regex]::Matches($listing, 'spark-(4\.\d+\.\d+)/') |
      ForEach-Object { [version]$_.Groups[1].Value } |
      Sort-Object -Descending
    if ($versions.Count -gt 0) { return $versions[0].ToString() }
  } catch {
    Write-Warning "Could not resolve latest Spark 4 from Apache: $($_.Exception.Message)"
  }
  Write-Warning "Falling back to Spark 4.1.2"
  return "4.1.2"
}

Write-Step "Resolving Spark version"
$SparkVersion = Resolve-SparkVersion $SparkVersion
Write-Host "Spark version: $SparkVersion"

Write-Step "Checking prerequisites"
$javaMajor = Get-JavaMajorVersion
if ($javaMajor -notin @(17, 21)) {
  throw "Java 17 or 21 is required. Install Temurin/OpenJDK 17 or 21, then rerun. Detected: $javaMajor"
}

$pythonLauncher = Get-PythonLauncher
if (-not $pythonLauncher) {
  throw "Python 3.10 or 3.11 is required. Install Python 3.11, ensure pip works, then rerun."
}

if ([string]::IsNullOrWhiteSpace($HadoopHome)) {
  if (Test-Path -LiteralPath "C:\hadoop-3.3.6\bin\winutils.exe") {
    $HadoopHome = "C:\hadoop-3.3.6"
  } else {
    $HadoopHome = "C:\hadoop"
  }
}

$hadoopBin = Join-Path $HadoopHome "bin"
$winutils = Join-Path $hadoopBin "winutils.exe"
$hadoopDll = Join-Path $hadoopBin "hadoop.dll"
if (-not ((Test-Path -LiteralPath $winutils) -and (Test-Path -LiteralPath $hadoopDll))) {
  if ($WinutilsBinSource) {
    Ensure-Directory $hadoopBin
    Copy-Item -LiteralPath (Join-Path $WinutilsBinSource "winutils.exe") -Destination $winutils -Force
    Copy-Item -LiteralPath (Join-Path $WinutilsBinSource "hadoop.dll") -Destination $hadoopDll -Force
  } else {
    throw "Missing Hadoop Windows helpers at $hadoopBin. Provide -WinutilsBinSource with winutils.exe and hadoop.dll, or install them after user confirmation."
  }
}

if ($CheckOnly) {
  Write-Host "Java major version: $javaMajor"
  Write-Host "Python launcher: $($pythonLauncher.Command) $($pythonLauncher.Args -join ' ')"
  Write-Host "SparkHome: $SparkHome"
  Write-Host "HadoopHome: $HadoopHome"
  Write-Host "Workspace: $Workspace"
  Write-Host "Prerequisite check passed."
  exit 0
}

Write-Step "Installing Apache Spark $SparkVersion"
$sparkRelease = Join-Path $SparkHome "RELEASE"
if (Test-Path -LiteralPath $SparkHome) {
  $existingRelease = if (Test-Path -LiteralPath $sparkRelease) { Get-Content -LiteralPath $sparkRelease -Raw } else { "" }
  if ($existingRelease -notmatch [regex]::Escape("Spark $SparkVersion")) {
    if (-not $ForceSparkReplace) {
      throw "$SparkHome exists and does not appear to contain Spark $SparkVersion. Rerun with -ForceSparkReplace to replace it."
    }
    Remove-Item -LiteralPath $SparkHome -Recurse -Force
  }
}

if (-not (Test-Path -LiteralPath $SparkHome)) {
  $tmp = Join-Path $env:TEMP "spark-install-$SparkVersion"
  $archive = Join-Path $tmp "spark-$SparkVersion-bin-hadoop3.tgz"
  $extractRoot = Join-Path $tmp "extract"
  Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
  Ensure-Directory $tmp
  Ensure-Directory $extractRoot
  $baseUrl = "https://dlcdn.apache.org/spark/spark-$SparkVersion/spark-$SparkVersion-bin-hadoop3.tgz"
  $shaUrl = "https://downloads.apache.org/spark/spark-$SparkVersion/spark-$SparkVersion-bin-hadoop3.tgz.sha512"
  Download-File $baseUrl $archive
  Verify-Sha512 $archive $shaUrl
  Invoke-NativeCommand "tar" @("-xzf", $archive, "-C", $extractRoot) "Failed to extract Apache Spark archive"
  Move-Item -LiteralPath (Join-Path $extractRoot "spark-$SparkVersion-bin-hadoop3") -Destination $SparkHome
}

Write-Step "Configuring user environment"
$javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", [EnvironmentVariableTarget]::Machine)
if (-not $javaHome) { $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", [EnvironmentVariableTarget]::User) }
if (-not $javaHome) {
  $javaPath = Get-CommandPath "java.exe"
  if ($javaPath) { $javaHome = Split-Path -Parent (Split-Path -Parent $javaPath) }
}
if (-not $javaHome) { throw "Could not determine JAVA_HOME." }

Set-UserEnvironment "JAVA_HOME" $javaHome
Set-UserEnvironment "SPARK_HOME" $SparkHome
Set-UserEnvironment "HADOOP_HOME" $HadoopHome
Set-UserEnvironment "PYSPARK_PYTHON" "python"
Set-UserEnvironment "SPARK_LOCAL_HOSTNAME" "localhost"
Add-UserPathEntry "%JAVA_HOME%\bin"
Add-UserPathEntry "%SPARK_HOME%\bin"
Add-UserPathEntry "%HADOOP_HOME%\bin"

$env:Path = "$javaHome\bin;$SparkHome\bin;$HadoopHome\bin;$env:Path"

Write-Step "Creating JupyterLab workspace"
Ensure-Directory $Workspace
$venvPython = Join-Path $Workspace ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $venvPython)) {
  Invoke-Python $pythonLauncher @("-m", "venv", (Join-Path $Workspace ".venv")) "Failed to create Python virtual environment"
}
if (-not (Test-Path -LiteralPath $venvPython)) {
  throw "Python virtual environment was not created at $venvPython"
}
Invoke-NativeCommand $venvPython @("-m", "pip", "install", "--upgrade", "pip") "Failed to upgrade pip"
Invoke-NativeCommand $venvPython @("-m", "pip", "install", "jupyterlab==4.5.8", "pyspark==$SparkVersion") "Failed to install base JupyterLab and PySpark packages"

$python3 = Join-Path $Workspace ".venv\Scripts\python3.exe"
if (-not (Test-Path -LiteralPath $python3)) {
  Copy-Item -LiteralPath $venvPython -Destination $python3
}

$launcher = Join-Path $Workspace "start-jupyter-lab.cmd"
$testScript = Join-Path $Workspace "test-pyspark.cmd"

@"
@echo off
set "JAVA_HOME=$javaHome"
set "SPARK_HOME=$SparkHome"
set "HADOOP_HOME=$HadoopHome"
set "SPARK_LOCAL_HOSTNAME=localhost"
set "PYSPARK_PYTHON=%~dp0.venv\Scripts\python.exe"
set "PYSPARK_DRIVER_PYTHON=%~dp0.venv\Scripts\python.exe"
set "PATH=%JAVA_HOME%\bin;%SPARK_HOME%\bin;%HADOOP_HOME%\bin;%PATH%"
cd /d "%~dp0"
"%~dp0.venv\Scripts\jupyter-lab.exe" --notebook-dir=.
"@ | Set-Content -LiteralPath $launcher -Encoding ASCII

@"
@echo off
set "JAVA_HOME=$javaHome"
set "SPARK_HOME=$SparkHome"
set "HADOOP_HOME=$HadoopHome"
set "SPARK_LOCAL_HOSTNAME=localhost"
set "PYSPARK_PYTHON=%~dp0.venv\Scripts\python.exe"
set "PYSPARK_DRIVER_PYTHON=%~dp0.venv\Scripts\python.exe"
set "PATH=%JAVA_HOME%\bin;%SPARK_HOME%\bin;%HADOOP_HOME%\bin;%PATH%"
cd /d "%~dp0"
"%~dp0.venv\Scripts\python.exe" -c "from pyspark.sql import SparkSession; spark = SparkSession.builder.appName('PySpark-Get-Started').getOrCreate(); df = spark.createDataFrame([('Alice', 25), ('Bob', 30)], ['Name', 'Age']); df.show(); print('SPARK_VERSION', spark.version); spark.stop()"
"@ | Set-Content -LiteralPath $testScript -Encoding ASCII

Write-Step "Verifying installation"
Invoke-NativeCommand (Join-Path $SparkHome "bin\spark-submit.cmd") @("--version") "spark-submit verification failed"
Invoke-NativeCommand $venvPython @("-c", "import pyspark; print(pyspark.__version__)") "PySpark import verification failed"
Invoke-NativeCommand $testScript @() "Generated PySpark smoke test failed"

Write-Host ""
Write-Host "Install complete."
Write-Host "Workspace: $Workspace"
Write-Host "Start JupyterLab: $launcher"
Write-Host "If Jupyter asks for a token, open the full URL printed by JupyterLab or run:"
Write-Host "  $Workspace\.venv\Scripts\jupyter.exe server list"
