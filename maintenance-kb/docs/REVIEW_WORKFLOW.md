# Review workflow

1. Preserve every source row in `data/raw`.
2. Normalize Arabic without changing the source label.
3. Move duplicates, compound work, handover procedures and unclear units to the review queue.
4. A technical reviewer approves category, unit and scope; finance separately approves prices.
5. Only reviewed rows enter `data/reviewed`; validator must pass before import.
6. Generate search text and embeddings only for `status=approved`.
7. A changed name, alias, unit or technical description changes the content hash and regenerates only that item's embedding.

Initial known blockers: duplicate names, 94 MISC items, 19 missing prices, two undefined units, classification and language issues. The historical 766-item file is a baseline, not an approved catalog.

