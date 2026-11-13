"""Execute the forecasting notebooks headless, in order (G06 -> G09 -> G10 -> G11).

The notebooks themselves are left untouched; each executed copy is written to
logs/executed/ so a failed cell can be inspected afterwards.
Exit code 0 = all notebooks ran; 1 = a notebook failed (its name is printed).
"""
import asyncio
import sys
import time
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=RuntimeWarning, module="zmq")
if sys.platform == "win32":  # zmq needs the selector loop on Windows; avoids a RuntimeWarning on stderr
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

import nbformat
from nbclient import NotebookClient
from nbclient.exceptions import CellExecutionError

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOKS = ["G06_Forecasting_Naive_MA", "G09_Forecasting_ETS", "G10_Forecasting_ARIMA", "G11_Forecast_Model_Selection"]
OUT = ROOT / "logs" / "executed"
OUT.mkdir(parents=True, exist_ok=True)

for name in NOTEBOOKS:
    path = ROOT / "notebooks" / f"{name}.ipynb"
    nb = nbformat.read(path, as_version=4)
    started = time.time()
    print(f"[{time.strftime('%H:%M:%S')}] running {name} ...", flush=True)
    client = NotebookClient(nb, timeout=1800, kernel_name="python3",
                            resources={"metadata": {"path": str(path.parent)}})  # notebooks use ../data and ../output
    try:
        client.execute()
    except CellExecutionError as err:
        nbformat.write(nb, OUT / f"{name}.FAILED.ipynb")
        print(f"FAILED {name}: {str(err).splitlines()[0] if str(err) else err}", flush=True)
        sys.exit(1)
    nbformat.write(nb, OUT / f"{name}.ipynb")
    print(f"[{time.strftime('%H:%M:%S')}] done {name} in {time.time() - started:.0f}s", flush=True)

print("all notebooks executed", flush=True)
