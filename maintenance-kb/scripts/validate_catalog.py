#!/usr/bin/env python3
import csv, sys
from pathlib import Path

UNITS={'عدد','متر','متر مربع','متر طولي','نقطة','زيارة','جهاز','طقم','قطعة','ساعة','يوم','خدمة'}
def rows(path):
    with Path(path).open(encoding='utf-8-sig', newline='') as f: return list(csv.DictReader(f))
def main():
    if len(sys.argv)!=4: raise SystemExit('usage: validate_catalog.py categories.csv items.csv aliases.csv')
    cats, items, aliases=map(rows,sys.argv[1:])
    errors=[]; cat_codes={r.get('category_code','').strip() for r in cats}; codes=set(); names=set(); alias_names=set()
    for n,r in enumerate(items,2):
        code=r.get('item_code','').strip(); cat=r.get('category_code','').strip(); name=r.get('normalized_name','').strip(); unit=r.get('unit','').strip()
        if not code or code in codes: errors.append(f'items:{n}: missing/duplicate item_code {code!r}')
        codes.add(code)
        if cat not in cat_codes: errors.append(f'items:{n}: unknown category {cat!r}')
        if not name or (cat,name) in names: errors.append(f'items:{n}: missing/duplicate normalized_name {name!r}')
        names.add((cat,name))
        if unit not in UNITS: errors.append(f'items:{n}: invalid unit {unit!r}')
        if code.startswith('MISC-') and not r.get('notes','').strip(): errors.append(f'items:{n}: MISC item requires review note')
        vals=[]
        for key in ('min_price','standard_price','max_price'):
            raw=r.get(key,'').strip(); vals.append(None if not raw else float(raw))
            if vals[-1] is not None and vals[-1]<0: errors.append(f'items:{n}: negative {key}')
        lo,std,hi=vals
        if lo is not None and std is not None and lo>std or std is not None and hi is not None and std>hi: errors.append(f'items:{n}: invalid price order')
    for n,r in enumerate(aliases,2):
        code=r.get('item_code','').strip(); alias=r.get('normalized_alias','').strip()
        if code not in codes: errors.append(f'aliases:{n}: unknown item {code!r}')
        if not alias or alias in alias_names: errors.append(f'aliases:{n}: missing/duplicate normalized_alias {alias!r}')
        alias_names.add(alias)
    if errors: print('\n'.join(errors),file=sys.stderr); raise SystemExit(1)
    print(f'valid: {len(cats)} categories, {len(items)} items, {len(aliases)} aliases')
if __name__=='__main__': main()

