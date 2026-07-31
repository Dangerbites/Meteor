# check_av.py
import sys

# Tell the user exactly which Python is being used.
print(f"Python executable: {sys.executable}")

try:
    import av
    print(f"PyAV version: {av.__version__}")
    print("av package is INSTALLED and importable.")
    sys.exit(0)
except ImportError as e:
    print(f"ERROR: av package is NOT importable.\n{e}")
    sys.exit(1)