#!/usr/bin/env python3
"""
تحميل بيانات كتالوج الصيانة (التصنيفات + 766 بند + المرادفات) من ملفات CSV
الموجودة في ../seed/ إلى قاعدة بيانات PostgreSQL بعد تطبيق schema_postgres.sql.

الاستخدام:
    export PGHOST=localhost PGPORT=5433 PGDATABASE=azab_maintenance \
           PGUSER=app_user PGPASSWORD=...
    python3 load_seed_data.py

يعتمد فقط على psycopg2 (pip install psycopg2-binary --break-system-packages).
لا يحسب أي embeddings هنا — هذا دور generate_embeddings.py بعد التحميل.
"""
import csv
import os
import sys
from pathlib import Path

try:
    import psycopg2
except ImportError:
    sys.exit("يجب تثبيت psycopg2 أولاً: pip install psycopg2-binary --break-system-packages")

SEED_DIR = Path(__file__).resolve().parent.parent / "seed"
CATEGORY_CSV = SEED_DIR / "import_maintenance_category.csv"
ITEM_CSV = SEED_DIR / "import_maintenance_service_item.csv"


def get_conn():
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "azab_maintenance"),
        user=os.environ.get("PGUSER", "app_user"),
        password=os.environ.get("PGPASSWORD", ""),
    )


def load_categories(cur):
    with open(CATEGORY_CSV, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        rows = [
            (r["category_code"], r["category_name"], r["description"], r["is_active"] == "1")
            for r in reader
        ]
    cur.executemany(
        """INSERT INTO maintenance_category (category_code, category_name, description, is_active)
           VALUES (%s, %s, %s, %s)
           ON CONFLICT (category_code) DO NOTHING""",
        rows,
    )
    print(f"✔ تصنيفات: {len(rows)}")


def load_items_and_aliases(cur):
    item_rows = []
    alias_rows = []
    with open(ITEM_CSV, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for r in reader:
            item_rows.append((
                r["item_code"],
                r["category"],
                r["item_name"],
                r["unit"],
                float(r["standard_price"]) if r["standard_price"] else None,
                float(r["min_price"]) if r["min_price"] else None,
                float(r["max_price"]) if r["max_price"] else None,
                r["status"],
                r["source"],
                r["is_active"] == "1",
            ))
            aliases = (r.get("aliases") or "").strip()
            if aliases:
                # الفاصل المستخدم في الكتالوج هو "، " (فاصلة عربية)
                for a in aliases.split("،"):
                    a = a.strip()
                    if a:
                        alias_rows.append((r["item_code"], a))

    cur.executemany(
        """INSERT INTO maintenance_service_item
               (item_code, category_code, item_name, unit, standard_price,
                min_price, max_price, status, source, is_active)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
           ON CONFLICT (item_code) DO NOTHING""",
        item_rows,
    )
    print(f"✔ بنود الكتالوج: {len(item_rows)}")

    cur.executemany(
        """INSERT INTO maintenance_service_item_alias (item_code, alias_text)
           VALUES (%s, %s)""",
        alias_rows,
    )
    print(f"✔ مرادفات: {len(alias_rows)}")


def main():
    conn = get_conn()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            load_categories(cur)
            load_items_and_aliases(cur)
        conn.commit()
        print("تم التحميل بنجاح ✅")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
