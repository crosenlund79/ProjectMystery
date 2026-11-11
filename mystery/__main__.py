import sys

from mystery.cli import main

if __name__ == "__main__":  # guard: Windows multiprocessing re-imports the main module
    sys.exit(main())
