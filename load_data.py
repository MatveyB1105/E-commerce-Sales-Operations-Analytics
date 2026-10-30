import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.types import Text

import pandas as pd

SHEMA = "analytics"

ROOT_DIR = Path(__file__).resolve().parent

DATA_DIR = ROOT_DIR / "data"

load_dotenv(ROOT_DIR / ".env")
DB_URL = os.getenv("DB_URL")

files = {}

engine = create_engine(
    DB_URL,
    pool_pre_ping=True,
    connect_args={"client_encoding": "utf8"},
)

for entry in os.scandir(DATA_DIR):
    if entry.is_file():
        file_name = Path(entry).name
        file_name_with_no_ext = Path(entry).stem
        files[file_name_with_no_ext] = file_name

for stem, filename in files.items():
    df = pd.read_csv(
        DATA_DIR / filename,
        dtype=str,
        keep_default_na=False,
        low_memory=False,
    )

    df = df.replace("", None)
    column_types = {
        column: Text()
        for column in df.columns
    }

    df.to_sql(
        stem,
        engine,
        schema=SHEMA,
        if_exists="replace",
        index=False,
        method="multi",
        chunksize=5000,
    )

    print(f"Loaded: {stem} columns: {len(df.columns)} rows: {len(df)}")

try:
    with engine.connect() as conn:
        print("OK:", conn.execute(text("SELECT version()")).scalar())
except Exception as e:
    print("REAL ERROR:", repr(e))
    print(str(e))