#!/usr/bin/env python3
import argparse, csv
from pathlib import Path
import psycopg

def load(path):
    with path.open(encoding='utf-8-sig',newline='') as f: return list(csv.DictReader(f))

def main():
    p=argparse.ArgumentParser(); p.add_argument('--database-url',required=True); p.add_argument('--data-dir',type=Path,required=True); a=p.parse_args()
    cats=load(a.data_dir/'maintenance_categories.csv'); items=load(a.data_dir/'maintenance_items.csv'); aliases=load(a.data_dir/'maintenance_aliases.csv')
    with psycopg.connect(a.database_url) as con:
      with con.cursor() as cur:
        for r in cats:
          cur.execute('''INSERT INTO maintenance_kb.maintenance_categories(category_code,category_name,description)
          VALUES(%s,%s,%s) ON CONFLICT(category_code) DO UPDATE SET category_name=excluded.category_name,description=excluded.description,updated_at=now()''',(r['category_code'],r['category_name'],r.get('description') or None))
        for r in items:
          cur.execute('''INSERT INTO maintenance_kb.maintenance_service_items(item_code,category_id,item_name,normalized_name,unit,standard_price,min_price,max_price,status,source,notes)
          SELECT %s,c.id,%s,%s,%s,%s,%s,%s,%s,%s,%s FROM maintenance_kb.maintenance_categories c WHERE c.category_code=%s
          ON CONFLICT(item_code) DO UPDATE SET category_id=excluded.category_id,item_name=excluded.item_name,normalized_name=excluded.normalized_name,unit=excluded.unit,standard_price=excluded.standard_price,min_price=excluded.min_price,max_price=excluded.max_price,status=excluded.status,source=excluded.source,notes=excluded.notes,updated_at=now()''',
          (r['item_code'],r['item_name'],r['normalized_name'],r['unit'],r.get('standard_price') or None,r.get('min_price') or None,r.get('max_price') or None,r.get('status') or 'under_review',r.get('source') or 'reviewed_csv',r.get('notes') or None,r['category_code']))
        for r in aliases:
          cur.execute('''INSERT INTO maintenance_kb.maintenance_service_aliases(service_item_id,alias_text,normalized_alias,source)
          SELECT i.id,%s,%s,%s FROM maintenance_kb.maintenance_service_items i WHERE i.item_code=%s
          ON CONFLICT(normalized_alias) DO UPDATE SET alias_text=excluded.alias_text,source=excluded.source''',(r['alias_text'],r['normalized_alias'],r.get('source') or 'reviewed_csv',r['item_code']))
    print(f'imported {len(cats)} categories, {len(items)} items, {len(aliases)} aliases')
if __name__=='__main__': main()

