# SparkMonitor on Windows

Use this when a Windows JupyterLab notebook imports `sparkmonitor` but Spark fails while registering `sparkmonitor.listener.JupyterSparkMonitorListener`, or when the user needs proof that the SparkMonitor UI works.

## Required Mental Model

SparkMonitor requires all of these to work:

- Python package: `sparkmonitor`
- JupyterLab frontend extension: `sparkmonitor`
- IPython kernel extension: `sparkmonitor.kernelextension`
- JVM listener JAR matching Spark major/Scala binary version, for Spark 4 and Scala 2.13: `listener_spark4_2.13.jar`

Do not assume the frontend extension is enough. The kernel extension opens a local socket and sets `SPARKMONITOR_KERNEL_PORT`; the JVM listener connects to that port.

## Common Root Causes

### `SPARKMONITOR_KERNEL_PORT` is `ERRORNOTFOUND`

Likely cause: the IPython kernel extension did not load.

Check:

```powershell
$cfg = "$env:USERPROFILE\.ipython\profile_default\ipython_kernel_config.py"
Get-Content -LiteralPath $cfg -Tail 5
$bytes = [IO.File]::ReadAllBytes($cfg)
($bytes | Where-Object { $_ -eq 0 }).Count
```

The config must be plain text with no NUL bytes and must include exactly one active line:

```python
c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')
```

If the line appears as UTF-16-ish text with NUL bytes between characters, normalize the file to UTF-8 and keep one valid line.

### `ClassNotFoundException: sparkmonitor.listener.JupyterSparkMonitorListener`

Likely cause: Spark cannot load the listener JAR.

On Windows venvs, do not hardcode:

```python
".venv/lib/site-packages/sparkmonitor/listener_spark4_2.13.jar"
```

Use the installed package path:

```python
from pathlib import Path

listener_jar = Path(sparkmonitor.__path__[0]) / "listener_spark4_2.13.jar"
spark = (SparkSession.builder
    .config("spark.extraListeners", "sparkmonitor.listener.JupyterSparkMonitorListener")
    .config("spark.driver.extraClassPath", str(listener_jar))
    .appName("PySpark-Get-Started")
    .getOrCreate()
)
```

For Spark 3, choose the JAR matching Scala version:

- Spark 3 + Scala 2.12: `listener_spark3_2.12.jar`
- Spark 3 + Scala 2.13: `listener_spark3_2.13.jar`
- Spark 4 + Scala 2.13: `listener_spark4_2.13.jar`

The package's `sparkmonitor.kernelextension.configure(conf)` can auto-detect this from `SPARK_HOME\jars\spark-core_*.jar`, but explicit notebook config is often easier to verify.

## Verification Workflow

1. Check package versions:

```powershell
cd <workspace>
.\.venv\Scripts\python.exe -c "import pyspark, sparkmonitor; print(pyspark.__version__); print(sparkmonitor.__path__)"
.\.venv\Scripts\jupyter.exe labextension list
```

2. Validate the kernel extension in a real Jupyter kernel, not plain Python. A plain Python process cannot prove the frontend comm is open.

3. Start JupyterLab and open the target notebook. If an old failed Spark JVM exists, delete/restart the notebook session before rerunning.

4. Run a real Spark action, for example:

```python
sc = spark.sparkContext
sc.parallelize(range(100), 4).count()
```

or a DataFrame action:

```python
df_filtered.show()
```

5. Capture proof only after the browser shows a SparkMonitor panel with `Apache Spark`, executor/core counts, and completed jobs.

## Notes for Browser Verification

Use the available browser tooling to drive JupyterLab when possible. The success condition is visual: the notebook output must render the SparkMonitor UI, not just return a successful Spark count in a terminal.

If using the Jupyter REST API to restart sessions, include the `_xsrf` cookie header. An easier path is often:

```powershell
.\.venv\Scripts\jupyter.exe server list
```

then open the token URL in the browser, restart the kernel from the UI, and run cells manually or through browser automation.
