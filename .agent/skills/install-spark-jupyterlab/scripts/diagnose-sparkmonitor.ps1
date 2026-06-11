param(
    [string]$Workspace = "$env:USERPROFILE\jupyter-lab"
)

$ErrorActionPreference = "Stop"

function Write-Check($Name, $Value) {
    Write-Output ("{0}: {1}" -f $Name, $Value)
}

$venvPython = Join-Path $Workspace ".venv\Scripts\python.exe"
$jupyter = Join-Path $Workspace ".venv\Scripts\jupyter.exe"
$ipythonConfig = Join-Path $env:USERPROFILE ".ipython\profile_default\ipython_kernel_config.py"

Write-Check "Workspace" $Workspace
Write-Check "Python" $venvPython
Write-Check "Jupyter" $jupyter
Write-Check "IPython config" $ipythonConfig

if (!(Test-Path -LiteralPath $venvPython)) {
    throw "Missing venv Python at $venvPython"
}

& $venvPython -c "import sys, pyspark, sparkmonitor, pathlib; print('python=' + sys.version.split()[0]); print('pyspark=' + pyspark.__version__); print('sparkmonitor_path=' + sparkmonitor.__path__[0]); print('spark4_jar_exists=' + str((pathlib.Path(sparkmonitor.__path__[0]) / 'listener_spark4_2.13.jar').exists()))"

if (Test-Path -LiteralPath $jupyter) {
    & $jupyter labextension list
} else {
    Write-Warning "Missing Jupyter executable at $jupyter"
}

if (Test-Path -LiteralPath $ipythonConfig) {
    $bytes = [IO.File]::ReadAllBytes($ipythonConfig)
    $nulCount = ($bytes | Where-Object { $_ -eq 0 }).Count
    Write-Check "IPython config NUL bytes" $nulCount
    $extensionLines = Get-Content -LiteralPath $ipythonConfig | Where-Object { $_ -match "sparkmonitor\.kernelextension" }
    Write-Check "SparkMonitor kernel extension lines" ($extensionLines.Count)
    $extensionLines | ForEach-Object { Write-Output ("  " + $_) }
} else {
    Write-Warning "Missing IPython config. Create it and add c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')."
}

Write-Output ""
Write-Output "Expected notebook SparkSession classpath pattern:"
Write-Output "  listener_jar = Path(sparkmonitor.__path__[0]) / `"listener_spark4_2.13.jar`""
Write-Output "  .config(`"spark.driver.extraClassPath`", str(listener_jar))"
