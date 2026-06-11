# Windows Spark 4 Prerequisites

## Required components

- Java: OpenJDK/Temurin 17 or 21. Prefer Temurin 21 when installing new.
- Python: 3.10 or 3.11. Prefer Python 3.11. Avoid Python versions newer than Spark supports.
- Apache Spark: stable Spark 4 binary package prebuilt for Hadoop 3, for example `spark-4.1.2-bin-hadoop3.tgz`.
- Hadoop Windows helpers: `winutils.exe` and `hadoop.dll` in `%HADOOP_HOME%\bin`.
- Python packages in the project venv: `jupyterlab` and `pyspark==<spark-version>`.

## Recommended checks

```powershell
java --version
py -0p
py -3.11 --version
py -3.11 -m pip --version
Get-ChildItem Env:JAVA_HOME,SPARK_HOME,HADOOP_HOME,PYSPARK_PYTHON,SPARK_LOCAL_HOSTNAME -ErrorAction SilentlyContinue
```

## Missing prerequisites

Ask the user before installing missing Java or Python. Good Windows package ids when `winget` is available:

```powershell
winget install EclipseAdoptium.Temurin.21.JDK
winget install Python.Python.3.11
```

Hadoop helper binaries for Windows are not published as part of Apache Spark. Prefer an existing trusted local copy. If downloading from GitHub or another third-party source, explain that it is unofficial, name the source, and get confirmation before download.

## Verification

After setup, verify:

```powershell
spark-submit --version
cd C:\Users\<user>\jupyter-lab
.\.venv\Scripts\python.exe -c "import pyspark; print(pyspark.__version__)"
.\test-pyspark.cmd
.\start-jupyter-lab.cmd
```

JupyterLab should serve notebooks from the workspace directory. If a browser lands on `/login?next=%2Flab`, retrieve the current token:

```powershell
.\.venv\Scripts\jupyter.exe server list
```
