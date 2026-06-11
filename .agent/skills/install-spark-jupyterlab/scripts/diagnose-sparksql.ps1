[CmdletBinding()]
param(
  [string]$Workspace = (Join-Path $HOME "jupyter-lab")
)

$ErrorActionPreference = "Stop"

function Write-Value($Name, $Value) {
  Write-Output "$Name=$Value"
}

$venvPython = Join-Path $Workspace ".venv\Scripts\python.exe"
$jupyter = Join-Path $Workspace ".venv\Scripts\jupyter.exe"
$ipythonConfig = Join-Path $HOME ".ipython\profile_default\ipython_kernel_config.py"

Write-Output "Workspace: $Workspace"
Write-Output "Python: $venvPython"
Write-Output "Jupyter: $jupyter"
Write-Output "IPython config: $ipythonConfig"

if (-not (Test-Path -LiteralPath $venvPython)) {
  throw "Missing venv Python at $venvPython"
}

$packageProbe = Join-Path $env:TEMP "diagnose-sparksql-packages.py"
@'
import importlib.metadata as md
import importlib.util
import sys

print("python=" + sys.version.split()[0])
for dist in ["jupyterlab-sparksql", "ipywidgets", "jupyterlab-widgets", "widgetsnbextension", "pyspark"]:
    try:
        print(f"{dist}_version={md.version(dist)}")
    except md.PackageNotFoundError:
        print(f"{dist}_version=MISSING")

for name in ["jupyterlab_sparksql", "ipywidgets", "jupyterlab_widgets", "pyspark"]:
    spec = importlib.util.find_spec(name)
    print(f"{name}_path=" + (spec.origin if spec else "MISSING"))
'@ | Set-Content -LiteralPath $packageProbe -Encoding UTF8

& $venvPython $packageProbe
Remove-Item -LiteralPath $packageProbe -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $jupyter) {
  & $jupyter labextension list
} else {
  Write-Warning "Missing jupyter executable at $jupyter"
}

if (Test-Path -LiteralPath $ipythonConfig) {
  $bytes = [IO.File]::ReadAllBytes($ipythonConfig)
  Write-Value "IPython config NUL bytes" (($bytes | Where-Object { $_ -eq 0 }).Count)

  $lines = Get-Content -LiteralPath $ipythonConfig
  $sparkSqlLines = $lines | Where-Object { $_ -match "jupyterlab_sparksql\.magics" -and $_ -notmatch "^\s*#" }
  $sparkMonitorLines = $lines | Where-Object { $_ -match "sparkmonitor\.kernelextension" -and $_ -notmatch "^\s*#" }
  Write-Value "SparkSQL kernel extension lines" $sparkSqlLines.Count
  $sparkSqlLines | ForEach-Object { Write-Output "  $_" }
  Write-Value "SparkMonitor kernel extension lines" $sparkMonitorLines.Count
  $sparkMonitorLines | ForEach-Object { Write-Output "  $_" }
} else {
  Write-Warning "Missing IPython config. Create it and add c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')."
}

Write-Output ""
Write-Output "Fresh kernel magic check:"
$kernelProbe = Join-Path $env:TEMP "diagnose-sparksql-kernel.py"
@'
import jupyter_client

km = jupyter_client.KernelManager(kernel_name="python3")
km.start_kernel()
kc = km.client()
kc.start_channels()
kc.wait_for_ready(timeout=60)
try:
    kc.execute('print(get_ipython().find_cell_magic("sql") is not None)')
    output = []
    while True:
        msg = kc.get_iopub_msg(timeout=60)
        msg_type = msg["header"]["msg_type"]
        content = msg["content"]
        if msg_type == "stream":
            output.append(content["text"].strip())
        elif msg_type == "execute_result":
            output.append(str(content["data"].get("text/plain", "")))
        elif msg_type == "error":
            output.append("ERROR:" + content["ename"] + ":" + content["evalue"])
        elif msg_type == "status" and content.get("execution_state") == "idle":
            break
    print("sql_magic_registered=" + "|".join(output))
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)
'@ | Set-Content -LiteralPath $kernelProbe -Encoding UTF8

& $venvPython $kernelProbe
Remove-Item -LiteralPath $kernelProbe -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "Expected repair line:"
Write-Output "  c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')"
Write-Output ""
Write-Output "Minimal notebook proof:"
Write-Output "  df_filtered.createOrReplaceTempView(`"df_filtered`")"
Write-Output "  %%sql -n 10"
Write-Output "  select item, qty, score from df_filtered order by item"
