# Alazab Maintenance Knowledge Base

Isolated maintenance-catalog and semantic-search layer for UberFix. This directory does not modify pgvector extension sources.

## Apply

```bash
for file in migrations/*.sql; do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"; done
python3 scripts/validate_catalog.py data/reviewed/maintenance_categories.csv data/reviewed/maintenance_items.csv data/reviewed/maintenance_aliases.csv
python3 scripts/import_catalog.py --database-url "$DATABASE_URL" --data-dir data/reviewed
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/test_catalog_integrity.sql
```

Raw data must pass human review before moving to `data/reviewed`. Embeddings are generated only for approved items. Exact vector scan is intentional for the initial catalog size; add HNSW only after fixing model dimensions and measuring a need.

