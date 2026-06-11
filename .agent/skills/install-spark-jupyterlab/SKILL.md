---
name: install-spark-jupyterlab
description: Install, repair, or debug a local Apache Spark 4 setup for JupyterLab on Windows. Use when the user wants Apache Spark, PySpark, SparkMonitor, jupyterlab-sparksql, SparkSQL %%sql magics, JupyterLab configured locally on a Windows PC, or JupyterLab terminal launcher failures. Covers Java/Python prerequisite checks, Spark download and extraction, Hadoop winutils/hadoop.dll setup, user environment variables, launch scripts, token-login explanation, smoke-test verification, fixing SparkMonitor listener/JupyterLab extension errors such as SPARKMONITOR_KERNEL_PORT ERRORNOTFOUND or ClassNotFoundException for JupyterSparkMonitorListener, fixing jupyterlab-sparksql errors where %%sql is interpreted as Python, the sql cell magic is missing, or SparkSQL widgets fail to render in JupyterLab 4, and fixing terminal errors such as Launcher Error / Unhandled error caused by broken pywinpty/winpty.
---

# Install Spark JupyterLab

## Workflow

Use this skill to set up Apache Spark 4 for local JupyterLab use on Windows.

1. Inspect the machine first:
   - Java must be OpenJDK/Temurin 17 or 21.
   - Python must be 3.10 or 3.11; prefer 3.11.
   - Hadoop Windows helpers must provide `winutils.exe` and `hadoop.dll`.
   - Existing `SPARK_HOME`, `HADOOP_HOME`, `JAVA_HOME`, PATH entries, and running Jupyter servers matter.
2. Explain missing prerequisites and ask before installing Java/Python or downloading helper binaries.
3. Prefer the bundled script `scripts/install-spark-jupyterlab.ps1` for repeatable installation. Read it before running if the target PC differs from the defaults.
4. Use the reference checklist in `references/windows-prerequisites.md` when troubleshooting or when the script stops on a missing dependency.
5. For SparkMonitor install or debugging, read `references/sparkmonitor-windows.md` before changing code or configuration.
6. For `jupyterlab-sparksql` install or debugging, read `references/sparksql-windows.md` before changing code or configuration.
7. For JupyterLab terminal launcher failures, read `references/jupyter-terminal-windows.md` before reinstalling JupyterLab or changing unrelated Spark packages.
8. Verify with `spark-submit --version`, PySpark import/version, the generated `test-pyspark.cmd`, a JupyterLab startup probe, and, when SparkMonitor, SparkSQL magics, or terminals are involved, a real browser/notebook run that shows the relevant UI result.
9. Finish with a user-facing explanation in the user's language when obvious.

## Defaults

Use these defaults unless the user asks otherwise:

- Spark version: latest stable Spark 4 checked from Apache at install time; fallback to `4.1.2`.
- Spark home: `C:\spark`.
- Hadoop home: reuse existing `C:\hadoop-3.3.6` when valid; otherwise use `C:\hadoop`.
- Jupyter workspace: `C:\Users\<user>\jupyter-lab`.
- Python venv: `<workspace>\.venv`.
- Environment scope: user-level variables, not system-level variables.
- Jupyter auth: keep default token login; do not disable auth or set a password unless the user asks.

Keep Apache Spark and the Python `pyspark` package on the same version.

## SparkMonitor

SparkMonitor has two parts: the JupyterLab frontend extension and the IPython kernel extension. The frontend can be installed while the kernel side is still broken, so verify both.

Start with:

```powershell
$skill = "C:\Users\<user>\.agents\skills\install-spark-jupyterlab"
& "$skill\scripts\diagnose-sparkmonitor.ps1" -Workspace "C:\Users\<user>\jupyter-lab"
```

If Spark starts with `SPARKMONITOR_KERNEL_PORT` set to `ERRORNOTFOUND`, repair the IPython kernel config as described in `references/sparkmonitor-windows.md`.

If Spark fails with `ClassNotFoundException: sparkmonitor.listener.JupyterSparkMonitorListener`, fix the notebook/classpath to use the listener JAR from the installed Python package path, not a hardcoded Linux-style `.venv/lib/...` path.

## SparkSQL Magic

`jupyterlab-sparksql` has a JupyterLab frontend extension and an IPython kernel magic. The frontend can be installed while `%%sql` is still interpreted as Python, so verify the kernel side.

Start with:

```powershell
$skill = "C:\Users\<user>\.agents\skills\install-spark-jupyterlab"
& "$skill\scripts\diagnose-sparksql.ps1" -Workspace "C:\Users\<user>\jupyter-lab"
```

To install or repair the package and kernel autoload:

```powershell
$skill = "C:\Users\<user>\.agents\skills\install-spark-jupyterlab"
& "$skill\scripts\install-sparksql.ps1" -Workspace "C:\Users\<user>\jupyter-lab" -RepairConfig
```

If `%%sql` raises `SyntaxError` or `Cell magic %%sql not found`, repair the IPython kernel config as described in `references/sparksql-windows.md`. Keep any existing SparkMonitor line intact.

If `%%sql` executes but JupyterLab shows `Error displaying widget`, use JupyterLab 4-compatible widget packages as described in `references/sparksql-windows.md`, then restart JupyterLab and the notebook kernel.

## JupyterLab Terminal Launcher

When the Terminal launcher tile opens a `Launcher Error` dialog with `Unhandled error`, do not assume the frontend is broken. On Windows, first inspect the Jupyter server log and the terminal backend packages.

Start with `references/jupyter-terminal-windows.md` if any of these are true:

- Browser dialog says `Launcher Error` / `Unhandled error` after clicking Terminal.
- Server log contains `AttributeError: type object 'object' has no attribute 'spawn'`.
- Importing `winpty` in the Jupyter venv fails with `ImportError: DLL load failed while importing winpty`.

The common repair is a targeted reinstall or upgrade of `pywinpty` in the same venv that runs JupyterLab, followed by a JupyterLab server restart. Avoid broad JupyterLab reinstalls unless the focused `pywinpty` repair fails.

## Installer Script

Run from PowerShell:

```powershell
$skill = "C:\Users\<user>\.agents\skills\install-spark-jupyterlab"
& "$skill\scripts\install-spark-jupyterlab.ps1"
```

Useful options:

```powershell
# Check current machine without changing it.
& "$skill\scripts\install-spark-jupyterlab.ps1" -CheckOnly

# Use a specific Spark 4 version instead of resolving latest.
& "$skill\scripts\install-spark-jupyterlab.ps1" -SparkVersion 4.1.2

# Provide a folder containing winutils.exe and hadoop.dll.
& "$skill\scripts\install-spark-jupyterlab.ps1" -WinutilsBinSource "C:\Downloads\hadoop-3.3.6\bin"

# Install to a different notebook workspace.
& "$skill\scripts\install-spark-jupyterlab.ps1" -Workspace "D:\jupyter-lab"
```

The script intentionally does not silently install Java/Python or fetch unofficial winutils binaries. If those are missing, stop and get explicit user confirmation for the specific install/download.

## Final User Message

After a successful install, tell the user:

- Where Spark, Hadoop helpers, and the Jupyter workspace were installed.
- How to start JupyterLab: `<workspace>\start-jupyter-lab.cmd`.
- How to test PySpark: `<workspace>\test-pyspark.cmd`.
- That Jupyter token login is normal and local: open the full printed URL containing `?token=...`, or retrieve it with:

```powershell
cd <workspace>
.\.venv\Scripts\jupyter.exe server list
```

- That notebooks should be created under `<workspace>` unless they intentionally choose another folder.
