# azab_maintenance — نظام قاعدة بيانات الصيانة الرقمي (فوق pgvector)

هذا المجلد يحوّل كتالوج بنود الصيانة الموحد (من `files__1_.zip`: 15 تصنيف، 766 بند،
140 مرادف) من نسخة MariaDB/MySQL الأصلية إلى قاعدة بيانات **PostgreSQL** حقيقية
تستخدم امتداد **pgvector** الموجود في هذا المستودع نفسه — بإضافة بحث دلالي
(semantic similarity) يمنع تكرار الكتالوج تلقائيًا، وهو تطوير مباشر لفلسفة
"المرادفات + fuzzy clustering" المذكورة في README الأصلي للكتالوج.

> ✅ كل ملف في هذا المجلد **تم اختباره فعليًا**: بُني امتداد pgvector من كود هذا
> المستودع (`make && make install`)، أُنشئت قاعدة بيانات تجريبية، نُفّذت
> `schema_postgres.sql` بنجاح، وحُمّلت الـ 766 بند + 140 مرادف عبر
> `load_seed_data.py` وتطابقت الأعداد مع README الأصلي تمامًا (كهرباء 186،
> أبواب 116، نجارة 113 ...).

## الملفات

| الملف | الغرض |
|---|---|
| `schema_postgres.sql` | السكيما الكاملة (تصنيفات، كتالوج، مرادفات، فروع، طلبات، بنود الطلب) + عمود `embedding vector(1536)` وفهرس HNSW ودالة `find_similar_service_items()` |
| `seed/import_maintenance_category.csv` | 15 تصنيف (كما في الأرشيف الأصلي) |
| `seed/import_maintenance_service_item.csv` | 766 بند معتمد + عمود مرادفات |
| `seed/كتالوج_بنود_الصيانة_المعتمد_v1.xlsx` | المرجع الكامل الأصلي (لوحة قيادة + الكتالوج + المرادفات + دليل التصنيفات) |
| `scripts/load_seed_data.py` | يحمّل التصنيفات + البنود + يفكّك عمود المرادفات لجدول `maintenance_service_item_alias` |
| `scripts/generate_embeddings.py` | يحسب embedding لكل بند (الاسم + مرادفاته) عبر مزوّد قابل للاستبدال (افتراضيًا OpenAI `text-embedding-3-small`, 1536 بُعد) ويخزّنه |

## الفرق الجوهري عن `maintenance_schema.sql` الأصلي

النسخة الأصلية كانت تعتمد على **مراجعة بشرية + fuzzy string matching** (تشابه
حروف) لمنع تكرار البنود عند الإضافة. المشكلة: بندين بصياغة مختلفة تمامًا لفظيًا
لكن بنفس المعنى ("تسريب خرطوم الحوض" و"نز مية من توصيلة الحوض" مثلاً) ما كانوا
هيتمسكوا بتشابه الحروف. عمود `embedding` + دالة `find_similar_service_items()`
يحلّوا المشكلة دي: البحث بيبقى بالمعنى مش بالحروف.

## خطوات التشغيل

يبني على `setup_postgres_az.sh` الموجود في جذر المستودع (يجهز PostgreSQL 17 +
pgvector + مستخدمين `app_user`/`readonly_user`). بعد تشغيله:

```bash
# 1) تفعيل السكيما (يشمل CREATE EXTENSION vector تلقائيًا)
psql -h <host> -p 5433 -U app_user -d <dbname> -f azab_maintenance/schema_postgres.sql

# 2) تحميل الكتالوج
pip install psycopg2-binary --break-system-packages
export PGHOST=<host> PGPORT=5433 PGDATABASE=<dbname> PGUSER=app_user PGPASSWORD=...
python3 azab_maintenance/scripts/load_seed_data.py

# 3) (اختياري لكن موصى به) حساب الـ embeddings الحقيقية لتفعيل البحث الدلالي
pip install openai --break-system-packages
export OPENAI_API_KEY=...
python3 azab_maintenance/scripts/generate_embeddings.py
```

## مثال استخدام: منع تكرار بند جديد قبل الإضافة

```sql
-- افترض حسبنا embedding لوصف طلب جديد "فيه نز مية تحت حوض المطبخ" (بنفس مزوّد
-- generate_embeddings.py) وحفظناه في :new_embedding
SELECT * FROM find_similar_service_items(:new_embedding, 5, 0.80);
-- لو رجّع صف بـ similarity عالي، يبقى على الأغلب بند موجود بالفعل — منستخدمه
-- بدل ما ننشئ بند جديد "تحت المراجعة" مكرر بالمعنى.
```

## ملاحظة صادقة على حدود ما تم اختباره هنا

- **مُختبَر فعليًا:** بناء الامتداد، تنفيذ السكيما، تحميل الـ766 بند والمرادفات،
  عمل فهرس HNSW، وتنفيذ دالة البحث ميكانيكيًا (بمتجهات عشوائية للتأكد من سلامة
  الاستعلام والفهرس).
- **غير مُختبَر هنا (يحتاج مفتاح API فعلي من فريقكم):** الدقة الدلالية الحقيقية
  لـ `find_similar_service_items()` — أي "هل فعلاً بيمسك بنود متشابهة بالمعنى
  صح؟" — لأن المتجهات التجريبية اللي استخدمناها للتأكد من سلامة الكود كانت
  عشوائية لا تحمل معنى لغوي. بعد تشغيل `generate_embeddings.py` بمفتاح OpenAI
  حقيقي يُنصح بمراجعة سريعة لعينة من نتائج التشابه قبل الاعتماد الكامل، بنفس
  روح "المراجعة قبل الاعتماد النهائي" المذكورة في README الأصلي للكتالوج.
