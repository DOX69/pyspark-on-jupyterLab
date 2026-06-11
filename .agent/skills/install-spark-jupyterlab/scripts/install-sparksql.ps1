[CmdletBinding()]
param(
  [string]$Workspace = (Join-Path $HOME "jupyter-lab"),
  [switch]$RepairConfig,
  [switch]$SkipWidgetUpgrade
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
  Write-Host ""
  Write-Host "==> $Message"
}

function Ensure-Directory($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Ensure-ConfigLine($Path, $Line) {
  $parent = Split-Path -Parent $Path
  Ensure-Directory $parent

  if (-not (Test-Path -LiteralPath $Path)) {
    "c = get_config()  #noqa" | Set-Content -LiteralPath $Path -Encoding UTF8
  }

  $bytes = [IO.File]::ReadAllBytes($Path)
  if (($bytes | Where-Object { $_ -eq 0 }).Count -gt 0) {
    throw "IPython config contains NUL bytes: $Path. Normalize it before appending SparkSQL config."
  }

  $lines = Get-Content -LiteralPath $Path
  $activeMatch = $lines | Where-Object { $_ -eq $Line -and $_ -notmatch "^\s*#" }
  if (-not $activeMatch) {
    Add-Content -LiteralPath $Path -Value $Line -Encoding UTF8
  }
}

$venvPython = Join-Path $Workspace ".venv\Scripts\python.exe"
$ipythonConfig = Join-Path $HOME ".ipython\profile_default\ipython_kernel_config.py"

Write-Step "Checking workspace"
Write-Host "Workspace: $Workspace"
Write-Host "Python: $venvPython"
if (-not (Test-Path -LiteralPath $venvPython)) {
  throw "Missing venv Python at $venvPython"
}

Write-Step "Installing jupyterlab-sparksql"
& $venvPython -m pip install --no-deps jupyterlab-sparksql
& $venvPython -m pip install pandas plotly

if (-not $SkipWidgetUpgrade) {
  $major = & $venvPython -c "import importlib.metadata as md; print(md.version('jupyterlab').split('.')[0])"
  if ([int]$major -ge 4) {
    Write-Step "Installing JupyterLab 4-compatible widget packages"
    & $venvPython -m pip install --upgrade "ipywidgets==8.1.8" "jupyterlab_widgets==3.0.16"
  } else {
    Write-Step "Keeping JupyterLab 3 widget packages"
    & $venvPython -m pip install "ipywidgets==7.7.2" "jupyterlab-widgets==1.1.4"
  }
}

if ($RepairConfig) {
  Write-Step "Repairing IPython kernel autoload"
  Ensure-ConfigLine $ipythonConfig "c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')"
  Write-Host "Updated: $ipythonConfig"
} else {
  Write-Host ""
  Write-Host "Pass -RepairConfig to add the IPython autoload line:"
  Write-Host "  c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')"
}

Write-Step "Summary"
& $venvPython -c "import importlib.metadata as md; [print(f'{d}={md.version(d)}') for d in ['jupyterlab', 'jupyterlab-sparksql', 'ipywidgets', 'jupyterlab-widgets']]"
Write-Host ""
Write-Host "Restart JupyterLab and the notebook kernel before validating %%sql."
