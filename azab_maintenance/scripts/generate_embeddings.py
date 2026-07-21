#!/usr/bin/env python3
"""
يحسب embedding لكل بند في maintenance_service_item (النص = item_name + كل
المرادفات المرتبطة به من maintenance_service_item_alias) ويخزّنه في العمود
embedding، تمهيدًا لاستخدام find_similar_service_items() في schema_postgres.sql.

مزوّد التضمين (embedding provider) قابل للتوصيل — الدالة embed_texts() هي
النقطة الوحيدة التي تحتاج تعديل لو غيّرت المزوّد. الجاهز الآن: OpenAI
(text-embedding-3-small, 1536 بُعد — نفس بُعد العمود في السكيما).

الاستخدام:
    export OPENAI_API_KEY=...
    export PGHOST=... PGPORT=... PGDATABASE=... PGUSER=... PGPASSWORD=...
    python3 generate_embeddings.py [--only-missing] [--batch-size 100]
"""
import argparse
import os
import sys

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.exit("يجب تثبيت psycopg2 أولاً: pip install psycopg2-binary --break-system-packages")

EMBEDDING_DIM = 1536


def embed_texts(texts: list[str]) -> list[list[float]]:
    """
    نقطة التوصيل الوحيدة: بدّل هذه الدالة لو استخدمت مزوّد تضمين غير OpenAI
    (Cohere / نموذج محلي عبر sentence-transformers / إلخ)، والمحافظة فقط على
    نفس EMBEDDING_DIM أو تعديله هنا + في schema_postgres.sql معًا.
    """
    try:
        from openai import OpenAI
    except ImportError:
        sys.exit("يجب تثبيت مكتبة openai أولاً: pip install openai --break-system-packages")

    client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    resp = client.embeddings.create(model="text-embedding-3-small", input=texts)
    return [d.embedding for d in resp.data]


def get_conn():
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "azab_maintenance"),
        user=os.environ.get("PGUSER", "app_user"),
        password=os.environ.get("PGPASSWORD", ""),
    )


def fetch_targets(cur, only_missing: bool):
    where = "WHERE i.embedding IS NULL" if only_missing else ""
    cur.execute(f"""
        SELECT i.item_code, i.item_name,
               COALESCE(string_agg(a.alias_text, '، '), '') AS aliases
        FROM maintenance_service_item i
        LEFT JOIN maintenance_service_item_alias a ON a.item_code = i.item_code
        {where}
        GROUP BY i.item_code, i.item_name
        ORDER BY i.item_code
    """)
    return cur.fetchall()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only-missing", action="store_true",
                         help="احسب فقط للبنود التي ما زال embedding فيها NULL")
    parser.add_argument("--batch-size", type=int, default=100)
    args = parser.parse_args()

    conn = get_conn()
    try:
        with conn.cursor() as cur:
            rows = fetch_targets(cur, args.only_missing)
            print(f"عدد البنود المطلوب حساب embedding لها: {len(rows)}")

            for i in range(0, len(rows), args.batch_size):
                batch = rows[i:i + args.batch_size]
                texts = [f"{name} {aliases}".strip() for _, name, aliases in batch]
                vectors = embed_texts(texts)
                if any(len(v) != EMBEDDING_DIM for v in vectors):
                    sys.exit(f"خطأ: بُعد المتجه المُستلَم لا يطابق EMBEDDING_DIM={EMBEDDING_DIM}")

                update_data = [
                    (vectors[j], texts[j], batch[j][0])
                    for j in range(len(batch))
                ]
                psycopg2.extras.execute_batch(
                    cur,
                    """UPDATE maintenance_service_item
                       SET embedding = %s::vector,
                           embedding_source_text = %s,
                           embedding_updated_at = now()
                       WHERE item_code = %s""",
                    update_data,
                )
                conn.commit()
                print(f"  ✔ تم {min(i + args.batch_size, len(rows))}/{len(rows)}")

        print("تم حساب كل الـembeddings بنجاح ✅")
        print("لتفعيل فهرس البحث السريع بعد التعبئة نفّذ في psql:")
        print("  REINDEX INDEX idx_item_embedding_hnsw;")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
