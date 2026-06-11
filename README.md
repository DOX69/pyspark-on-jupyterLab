# Portable PySpark & JupyterLab Workspace (pyspark-on-jupyterLab)

This repository provides a portable, reproducible Apache Spark and JupyterLab workspace designed for Windows. It is optimized to be installed and run with a single command.

This environment is fully documented and structured for both **human developers** and **AI assistants** (e.g., coding agents).

## Features
- **One-Command Setup**: Installs a local Python virtual environment, fetches Apache Spark 4.1.2, downloads Hadoop Windows helper binaries, and configures JupyterLab extensions.
- **SparkMonitor Integration**: Visualizes Spark jobs, executors, and cores directly in Jupyter notebooks.
- **SparkSQL %%sql Magic**: Allows executing SparkSQL cells natively in JupyterLab with table/widget rendering.
- **Portable Launchers**: Generates self-contained `.cmd` files that run without requiring manual path changes.
- **CI Tested**: Validated in Windows containers via GitHub Actions.

---

## Getting Started

### Prerequisites
1. **OS**: Windows (10/11)
2. **Python**: Python 3.10 or 3.11 installed and added to your system `PATH`.
3. **Java**: OpenJDK / Temurin JDK 17 or 21 installed and added to your system `PATH`.

### Installation
Run the setup script from an administrator or user PowerShell terminal:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

#### What the setup script does:
1. Creates a Python virtual environment (`.venv/`) locally.
2. Upgrades `pip` and installs dependencies from `requirements.txt`.
3. Automatically downloads missing Hadoop helpers (`winutils.exe`, `hadoop.dll`) to `C:\hadoop\bin`.
4. Installs Apache Spark 4.1.2 into `C:\spark` (if not already present).
5. Sets user-level environment variables (`JAVA_HOME`, `SPARK_HOME`, `HADOOP_HOME`, `PYSPARK_PYTHON`, `SPARK_LOCAL_HOSTNAME`).
6. Autoloads the SparkMonitor and SparkSQL kernel extensions in IPython.
7. Generates local wrappers `start-jupyter-lab.cmd` and `test-pyspark.cmd`.

---

## Usage

### 1. Test PySpark standalone
Run the test script to verify that PySpark can start a local SparkSession:
```cmd
.\test-pyspark.cmd
```

### 2. Start JupyterLab
Launch JupyterLab:
```cmd
.\start-jupyter-lab.cmd
```
*Note: JupyterLab uses a local security token at startup. Copy and paste the full printed URL containing `?token=...` into your browser if it does not open automatically.*

---

## 🤖 Guide for AI Assistants

This repository contains a local copy of the `install-spark-jupyterlab` agent skill in the [.agent/skills/install-spark-jupyterlab/](.agent/skills/install-spark-jupyterlab/) directory.

If you are an AI assistant helping a developer debug or customize this workspace:
1. **Read the Skill Instructions**: Read [.agent/skills/install-spark-jupyterlab/SKILL.md](.agent/skills/install-spark-jupyterlab/SKILL.md) to understand the workflow and configuration layout.
2. **Use the Diagnostic Scripts**:
   - To troubleshoot SparkMonitor issues, run:
     ```powershell
     powershell -File .agent/skills/install-spark-jupyterlab/scripts/diagnose-sparkmonitor.ps1 -Workspace .
     ```
   - To troubleshoot SparkSQL magics or widget rendering, run:
     ```powershell
     powershell -File .agent/skills/install-spark-jupyterlab/scripts/diagnose-sparksql.ps1 -Workspace .
     ```
3. **Reference Docs**: Look at the markdown files in `.agent/skills/install-spark-jupyterlab/references/` for details about Jupyter Terminal repair, SparkSQL configuration, and Windows prerequisite setups.

---

## Troubleshooting

### SparkMonitor: `SPARKMONITOR_KERNEL_PORT` is `ERRORNOTFOUND`
This means the IPython kernel extension is not loading. Verify that the line below is active in `%USERPROFILE%\.ipython\profile_default\ipython_kernel_config.py`:
```python
c.InteractiveShellApp.extensions.append('sparkmonitor.kernelextension')
```

### ClassNotFoundException for JupyterSparkMonitorListener
When creating a `SparkSession` in a notebook with SparkMonitor enabled, ensure you load the driver listener jar from the active site-packages directory rather than hardcoding it:
```python
from pathlib import Path
import sparkmonitor

listener_jar = Path(sparkmonitor.__path__[0]) / "listener_spark4_2.13.jar"
spark = (SparkSession.builder
    .config("spark.extraListeners", "sparkmonitor.listener.JupyterSparkMonitorListener")
    .config("spark.driver.extraClassPath", str(listener_jar))
    .appName("PySpark-Jupyter")
    .getOrCreate()
)
```

### Cell magic `%%sql` not found or raises SyntaxError
Make sure the SparkSQL magic is registered in `%USERPROFILE%\.ipython\profile_default\ipython_kernel_config.py`:
```python
c.InteractiveShellApp.extensions.append('jupyterlab_sparksql.magics')
```
And restart your Jupyter notebook kernel.
