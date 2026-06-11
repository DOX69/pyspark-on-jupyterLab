# JupyterLab Terminal Troubleshooting on Windows

Use this reference when JupyterLab itself opens, notebooks work, but the Terminal launcher tile fails with `Launcher Error` / `Unhandled error`.

## Failure Signature

The browser dialog is generic. The useful error is in the Jupyter server log:

```text
Uncaught exception POST /api/terminals
...
File "...site-packages\terminado\management.py", line 58, in __init__
  self.ptyproc = PtyProcessUnicode.spawn(**kwargs)
AttributeError: type object 'object' has no attribute 'spawn'
```

This means `terminado` failed to import a usable PTY backend. On Windows the usual backend is `pywinpty` / `winpty`. `terminado` catches the import failure and falls back to `object`, so terminal creation later crashes because `object` has no `spawn`.

The lower-level confirmation is usually:

```text
ImportError: DLL load failed while importing winpty: The specified module could not be found.
```

## 1. Identify the Running Jupyter Environment

Do not trust the first `jupyter` on `PATH`; Windows machines often have multiple Python installs. Find the process that owns the target port:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match 'jupyter-lab|jupyter lab|notebook' } |
  Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine |
  Format-List
```

Look for the venv path, for example:

```text
C:\Users\<user>\jupyter-lab\.venv\Scripts\jupyter-lab.exe --no-browser --port=8890
```

Use that venv's Python for every package and import check below:

```powershell
$Workspace = "C:\Users\<user>\jupyter-lab"
$Python = "$Workspace\.venv\Scripts\python.exe"
```

## 2. Reproduce the Server Error

Check the server status:

```powershell
Invoke-RestMethod -Uri "http://localhost:8890/api/status" -Method Get |
  ConvertTo-Json -Depth 5
```

Inspect recent logs in the workspace and Jupyter runtime:

```powershell
Get-ChildItem -Recurse -Force -File -Include *.log `
  -Path $Workspace, "$env:APPDATA\jupyter", "$env:USERPROFILE\.jupyter" `
  -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 20 FullName,Length,LastWriteTime

Get-Content -LiteralPath "$Workspace\jupyter-sparkmonitor.err.log" -Tail 160
```

If no log file is obvious, trigger the Terminal tile once in the browser and immediately inspect the most recently modified log.

## 3. Check Terminal Packages and Imports

List relevant package versions:

```powershell
& $Python -m pip show jupyterlab jupyter_server jupyter_server_terminals terminado pywinpty tornado
```

Check whether `winpty` can import and whether `terminado` sees a real PTY class:

```powershell
& $Python -c "import winpty; print('winpty import ok', winpty.__file__, winpty.__version__)"

& $Python -c "import terminado.management as m; print('PtyProcessUnicode:', m.PtyProcessUnicode, getattr(m.PtyProcessUnicode, '__module__', None), hasattr(m.PtyProcessUnicode, 'spawn'))"
```

Healthy output looks like:

```text
winpty import ok ...\site-packages\winpty\__init__.py 3.0.5
PtyProcessUnicode: <class 'winpty.ptyprocess.PtyProcess'> winpty.ptyprocess True
```

Broken output may show:

```text
PtyProcessUnicode: <class 'object'> builtins False
ImportError: DLL load failed while importing winpty
```

## 4. Repair pywinpty Only

Use the same venv Python that runs JupyterLab:

```powershell
& $Python -m pip install --upgrade --force-reinstall pywinpty
```

Then repeat the import checks:

```powershell
& $Python -c "import winpty; print('winpty import ok', winpty.__file__, winpty.__version__)"
& $Python -c "import terminado.management as m; print('PtyProcessUnicode:', m.PtyProcessUnicode, getattr(m.PtyProcessUnicode, '__module__', None), hasattr(m.PtyProcessUnicode, 'spawn'))"
```

Do not reinstall all of JupyterLab for this failure until the focused `pywinpty` repair fails. The terminal package can be broken while notebooks and Spark still work.

## 5. Restart JupyterLab

The running server has already imported `terminado`, so it may keep the broken `PtyProcessUnicode = object` value in memory. Restart the JupyterLab server after the package repair.

If the workspace has a launch script, prefer it because it preserves Spark environment variables:

```powershell
Get-Content -LiteralPath "$Workspace\start-jupyter-lab.cmd"
```

When restarting manually, preserve Spark-related variables from the launch script:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.3.9-hotspot\"
$env:SPARK_HOME = "C:\spark"
$env:HADOOP_HOME = "C:\hadoop-3.3.6"
$env:SPARK_LOCAL_HOSTNAME = "localhost"
$env:PYSPARK_PYTHON = "$Workspace\.venv\Scripts\python.exe"
$env:PYSPARK_DRIVER_PYTHON = "$Workspace\.venv\Scripts\python.exe"
$env:PATH = "$env:JAVA_HOME\bin;$env:SPARK_HOME\bin;$env:HADOOP_HOME\bin;$env:PATH"
```

Stop only the Jupyter server process tree for the target port. Avoid killing unrelated Python, Java, Node, or Spark processes by name. Verify the target process first with `Get-CimInstance Win32_Process`, then stop the Jupyter wrapper/server PIDs for that specific port.

Restart with the same port/token choices the user was using. Example for a local no-token lab during debugging:

```powershell
Start-Process `
  -FilePath "$Workspace\.venv\Scripts\jupyter-lab.exe" `
  -ArgumentList @("--no-browser", "--port=8890", "--ServerApp.token=", "--ServerApp.password=", "--notebook-dir=$Workspace") `
  -WorkingDirectory $Workspace `
  -WindowStyle Hidden
```

For normal installs, keep the default token login unless the user explicitly asks otherwise.

## 6. Validate Terminal Creation

First check the backend:

```powershell
Invoke-RestMethod -Uri "http://localhost:8890/api/status" -Method Get |
  ConvertTo-Json -Depth 5
```

For a direct POST test, Jupyter requires a matching XSRF cookie:

```powershell
$CookieFile = Join-Path $env:TEMP "jupyter-8890-cookies.txt"
Remove-Item -LiteralPath $CookieFile -ErrorAction SilentlyContinue

curl.exe -sS -c $CookieFile "http://localhost:8890/lab/workspaces/auto-q" | Out-Null

$Xsrf = Get-Content -LiteralPath $CookieFile |
  Where-Object { $_ -match '\s_xsrf\s' } |
  ForEach-Object { ($_ -split "`t")[-1] } |
  Select-Object -First 1

curl.exe -sS -i -b $CookieFile `
  -H "X-XSRFToken: $Xsrf" `
  -H "Content-Type: application/json" `
  -X POST -d "{}" `
  "http://localhost:8890/api/terminals"
```

Success returns HTTP `200 OK` and a terminal model:

```json
{"name": "1", "last_activity": "..."}
```

Then validate in the browser:

1. Open the JupyterLab URL.
2. Click the Terminal launcher tile.
3. Confirm a terminal panel opens and accepts a simple command such as `ls`.
4. If using browser automation, keep the validation narrow: click Terminal and inspect for a visible `.jp-Terminal` or `.xterm`, plus absence of a `Launcher Error` dialog.

## 7. Notes from the Debug Session That Produced This Runbook

The observed setup was:

- JupyterLab ran from `C:\Users\ggrft\jupyter-lab\.venv\Scripts\jupyter-lab.exe` on port `8890`.
- The shell's default `jupyter` command was not the same environment and did not even expose `jupyter server`, so process inspection was necessary.
- `jupyterlab`, `jupyter_server`, `terminado`, and `pywinpty` were installed, but `winpty` failed to import.
- Upgrading `pywinpty` from `3.0.4` to `3.0.5` fixed the import.
- Restarting JupyterLab was required because the old server process had cached the failed import.
- Backend validation with `/api/terminals` succeeded before browser validation.
