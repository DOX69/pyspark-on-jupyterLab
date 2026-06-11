# jupyterlab-sparksql on Windows

Use this when a Windows JupyterLab notebook should run SparkSQL through `%%sql`, but the cell is parsed as Python, raises `SyntaxError`, reports `Cell magic %%sql not found`, or renders `Error displaying widget`.

## Required Mental Model

`vule24/jupyterlab-sparksql` has separate pieces:

- Python package: `jupyterlab_sparksql`
- JupyterLab frontend extension: `jupyterlab-sparksql`
- IPython kernel extension: `jupyterlab_sparksql.magics`
- Widget rendering dependencies: `ipywidgets` and `jupyterlab_widgets`

The frontend extension only handles editor features such as syntax highlighting. The `%%sql` magic is registered only when the IPython extension loads in the kernel.

## Install or Repair

From the workspace:

```powershell
cd C:\Users\<user>\jupyter-lab
.\.venv\Scripts\python.exe -m pip install jupyterlab-sparksql
```

Or use the bundled installer:

```powershell
$skill = "C:\Users\<user>\.agents\skills\install-spark-jupyterlab"
& "$skill\scripts\install-sparksql.ps1" -Workspace "C:\Users\<user>\jupyter-lab" -RepairConfig
```

For JupyterLab 4, install widget packages compatible with JupyterLab 4:

```powershell
.\.venv\Scripts\python.exe -m pip install --upgrade "ipywidgets==8.1.8" "jupyterlab_widgets==3.0.16"
```

This intentionally conflicts with the strict pins in `jupyterlab-sparksql 1.1.0` (`ipywidgets==7.7.2`, `jupyterlab-widgets==1.1.4`). Those pins target the older JupyterLab 3 widget manager. Prefer the JupyterLab 4 widget manager when the local JupyterLab is version 4.

Add the IPython extension to the kernel config without removing SparkMonitor:

```python
c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')
c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')
```

The file is normally:

```powershell
C:\Users\<user>\.ipython\profile_default\ipython_kernel_config.py
```

Create it with `ipython profile create` if it does not exist. Keep the file as plain text with no NUL bytes.

## Common Root Causes

### `%%sql` is interpreted as Python

Likely cause: `jupyterlab_sparksql.magics` is not loaded in the kernel. The frontend extension may still appear installed.

Check:

```powershell
$cfg = "$env:USERPROFILE\.ipython\profile_default\ipython_kernel_config.py"
Get-Content -LiteralPath $cfg -Tail 10
```

The config must include exactly one active line:

```python
c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')
```

Restart the notebook kernel after changing this file.

### `Cell magic %%sql not found`

Likely cause: same as above, or the currently running kernel started before the config change. Restart the kernel or close old notebook sessions and open a fresh notebook.

### `Error displaying widget`

Likely cause: the local JupyterLab is 4.x but `jupyterlab-sparksql 1.1.0` installed the JupyterLab 3 widget manager (`jupyterlab-widgets 1.x`) through old pins.

Check:

```powershell
.\.venv\Scripts\jupyter.exe labextension list
.\.venv\Scripts\python.exe -m pip show ipywidgets jupyterlab-widgets widgetsnbextension
```

For JupyterLab 4, `@jupyter-widgets/jupyterlab-manager` should be enabled ok as a 5.x extension from `jupyterlab_widgets` 3.x.

### `jupyterlab-sparksql enabled X`

`jupyter labextension list` may still show:

```text
jupyterlab-sparksql v1.1.0 enabled X
```

This is expected with JupyterLab 4 because upstream declares JupyterLab 3 dependencies. It is a frontend compatibility warning. Do not treat it as proof that the `%%sql` magic is broken; verify the kernel magic and a real notebook execution.

## Verification Workflow

1. Run the diagnostic script:

```powershell
$skill = "C:\Users\<user>\.agents\skills\install-spark-jupyterlab"
& "$skill\scripts\diagnose-sparksql.ps1" -Workspace "C:\Users\<user>\jupyter-lab"
```

2. Start or reuse JupyterLab:

```powershell
cd C:\Users\<user>\jupyter-lab
.\start-jupyter-lab.cmd
```

3. In a fresh notebook kernel, create a Spark temp view:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("SparkSQLMagicProof").getOrCreate()
df_filtered = spark.createDataFrame([
    ("notebook", 3, 42.5),
    ("spark", 7, 99.0),
    ("sql", 5, 64.25),
], ["item", "qty", "score"])
df_filtered.createOrReplaceTempView("df_filtered")
```

4. Run the magic:

```sql
%%sql -n 10
select item, qty, score from df_filtered order by item
```

5. Capture proof only after the real JupyterLab UI shows a rendered result table. A terminal-only `spark.sql(...)` check is not enough for this workflow.

## Notes

- `jupyterlab-sparksql` automatically creates temp views for Spark DataFrames currently in the notebook namespace, but explicit `createOrReplaceTempView` makes validation clearer.
- Do not add SparkMonitor listener settings to a notebook that only proves SparkSQL magic unless the SparkMonitor UI is also open and expected. SparkMonitor is independent from the SparkSQL magic.
- `pip check` can report the old `jupyterlab-sparksql` widget pins as incompatible after upgrading widgets for JupyterLab 4. Record this as a known upstream metadata limitation if the real notebook proof works.
