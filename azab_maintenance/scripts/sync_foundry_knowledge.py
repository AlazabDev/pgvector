#!/usr/bin/env python3
"""
مزامنة كتالوج الصيانة المعتمد من قاعدة بيانات azab_maintenance (Postgres) إلى
معرفة الوكيل az-agent-maint على Azure AI Foundry Agent Service، عبر أداة
File Search (vector store) — بحيث لما بند صيانة يتغيّر أو يتّاعتمد جديد،
الوكيل يعرفه في محادثته التالية بدون إعادة تدريب أو تدخل يدوي.

الفكرة: نصدّر البنود المعتمدة (status = 'معتمد') من Postgres كملفات نصية
منظمة (ملف واحد لكل تصنيف)، نرفعها كـ Foundry files، ننشئ vector store جديد
منها، ثم نحدّث الوكيل az-agent-maint ليشير لهذا الـvector store الجديد —
ونحذف القديم بعد التأكد من نجاح التحديث (Foundry يسمح بـvector store واحد
فقط لكل وكيل، فالمزامنة هنا "استبدال كامل" مش "إضافة تراكمية").

⚠️ ملاحظة صدق مهمة: أسماء الدوال والتوقيعات هنا (agents_client.files.upload_and_poll،
agents_client.vector_stores.create_and_poll، FileSearchTool، update_agent...)
تم التحقق منها فعليًا مقابل حزمة azure-ai-agents (الإصدار المثبَّت وقت الكتابة:
1.1.0) بالفحص المباشر لتوقيعات الدوال — مش تخمين. لكن السكريبت نفسه **لم
يُختبر تشغيليًا** ضد مشروع Foundry حقيقي (محتاج PROJECT_ENDPOINT ومعرّف وكيل
فعليين ومصادقة Entra ID مش متاحين في بيئة التطوير دي). جرّبه أول مرة على وكيل
تجريبي/نسخة مش production قبل الاعتماد عليه.

المتطلبات:
    pip install azure-ai-agents azure-identity psycopg2-binary --break-system-packages

الاستخدام:
    export FOUNDRY_PROJECT_ENDPOINT="https://<project>.services.ai.azure.com/api/projects/<project-name>"
    export FOUNDRY_AGENT_ID="asst_xxxxxxxx"      # معرّف az-agent-maint من صفحة الوكيل في Foundry
    export PGHOST=... PGPORT=... PGDATABASE=... PGUSER=... PGPASSWORD=...
    az login   # أو أي طريقة توفر DefaultAzureCredential صلاحية على المشروع
    python3 sync_foundry_knowledge.py
"""
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

try:
    import psycopg2
except ImportError:
    sys.exit("يجب تثبيت psycopg2 أولاً: pip install psycopg2-binary --break-system-packages")

try:
    from azure.ai.agents import AgentsClient
    from azure.ai.agents.models import FileSearchTool, FilePurpose
    from azure.identity import DefaultAzureCredential
except ImportError:
    sys.exit("يجب تثبيت azure-ai-agents وazure-identity أولاً:\n"
              "  pip install azure-ai-agents azure-identity --break-system-packages")


def get_pg_conn():
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "azab_maintenance"),
        user=os.environ.get("PGUSER", "app_user"),
        password=os.environ.get("PGPASSWORD", ""),
    )


def export_catalog_as_markdown_files(conn, out_dir: Path) -> list[Path]:
    """
    يصدّر كل تصنيف نشط كملف Markdown مستقل — تقسيم منطقي يخلي كل chunk في
    الـvector store متماسك (بنود نفس التصنيف مع بعض) بدل ملف واحد ضخم.
    نُصدّر فقط البنود بحالة 'معتمد' (مش 'تحت المراجعة' أو 'ملغي') لأن دي البنود
    الرسمية اللي المفروض الوكيل يعتمد عليها في الرد على المستخدمين.
    """
    cur = conn.cursor()
    cur.execute("""
        SELECT c.category_code, c.category_name
        FROM maintenance_category c
        WHERE c.is_active = TRUE
        ORDER BY c.category_code
    """)
    categories = cur.fetchall()

    files = []
    for category_code, category_name in categories:
        cur.execute("""
            SELECT i.item_code, i.item_name, i.unit, i.standard_price,
                   i.min_price, i.max_price,
                   COALESCE(string_agg(DISTINCT a.alias_text, '، '), '') AS aliases
            FROM maintenance_service_item i
            LEFT JOIN maintenance_service_item_alias a ON a.item_code = i.item_code
            WHERE i.category_code = %s AND i.status = 'معتمد' AND i.is_active = TRUE
            GROUP BY i.item_code, i.item_name, i.unit, i.standard_price,
                     i.min_price, i.max_price
            ORDER BY i.item_code
        """, (category_code,))
        items = cur.fetchall()
        if not items:
            continue

        lines = [f"# كتالوج بنود الصيانة — {category_name} ({category_code})\n"]
        for item_code, item_name, unit, std_price, min_price, max_price, aliases in items:
            lines.append(f"## {item_name}  (`{item_code}`)")
            lines.append(f"- الوحدة: {unit}")
            if std_price is not None:
                price_line = f"- السعر المعياري: {std_price:g} جنيه"
                if min_price is not None and max_price is not None:
                    price_line += f" (يتراوح تاريخيًا بين {min_price:g} و{max_price:g})"
                lines.append(price_line)
            if aliases:
                lines.append(f"- صياغات/أسماء بديلة معروفة لنفس البند: {aliases}")
            lines.append("")

        path = out_dir / f"{category_code}.md"
        path.write_text("\n".join(lines), encoding="utf-8")
        files.append(path)
        print(f"  ✔ {category_name} ({category_code}): {len(items)} بند → {path.name}")

    cur.close()
    return files


def sync(agents_client: AgentsClient, agent_id: str, md_files: list[Path]):
    # 1) احفظ الـvector store القديم المرتبط بالوكيل (لو موجود) عشان نحذفه
    #    بعد التأكد من نجاح التبديل — مش قبل، تحسبًا لأي فشل في المنتصف.
    agent = agents_client.get_agent(agent_id)
    old_vector_store_ids = []
    if agent.tool_resources and getattr(agent.tool_resources, "file_search", None):
        old_vector_store_ids = list(agent.tool_resources.file_search.vector_store_ids or [])
    print(f"الـvector store الحالي المرتبط بالوكيل: {old_vector_store_ids or 'لا يوجد'}")

    # 2) ارفع الملفات الجديدة
    uploaded_file_ids = []
    for path in md_files:
        file_info = agents_client.files.upload_and_poll(
            file_path=str(path), purpose=FilePurpose.AGENTS
        )
        uploaded_file_ids.append(file_info.id)
    print(f"تم رفع {len(uploaded_file_ids)} ملف")

    # 3) أنشئ vector store جديد منها
    vs_name = f"azab-maintenance-catalog-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}"
    vector_store = agents_client.vector_stores.create_and_poll(
        file_ids=uploaded_file_ids, name=vs_name
    )
    print(f"تم إنشاء vector store جديد: {vector_store.id} ({vs_name})")

    # 4) حدّث الوكيل ليشير للـvector store الجديد
    file_search = FileSearchTool(vector_store_ids=[vector_store.id])
    agents_client.update_agent(
        agent_id=agent_id,
        tools=file_search.definitions,
        tool_resources=file_search.resources,
    )
    print(f"تم تحديث الوكيل {agent_id} ليستخدم vector store: {vector_store.id}")

    # 5) نظّف القديم بعد التأكد إن التحديث نجح
    for old_id in old_vector_store_ids:
        try:
            agents_client.vector_stores.delete(old_id)
            print(f"تم حذف الـvector store القديم: {old_id}")
        except Exception as e:  # لا نوقف العملية لو الحذف فشل — التحديث الأهم نجح فعلاً
            print(f"⚠ تعذّر حذف الـvector store القديم {old_id}: {e}", file=sys.stderr)


def main():
    endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    agent_id = os.environ.get("FOUNDRY_AGENT_ID")
    if not endpoint or not agent_id:
        sys.exit("يجب ضبط FOUNDRY_PROJECT_ENDPOINT و FOUNDRY_AGENT_ID كمتغيرات بيئة أولاً")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        conn = get_pg_conn()
        try:
            print("تصدير الكتالوج المعتمد من قاعدة البيانات...")
            md_files = export_catalog_as_markdown_files(conn, tmp_path)
        finally:
            conn.close()

        if not md_files:
            sys.exit("لا يوجد بنود بحالة 'معتمد' للمزامنة — تأكد من تحميل الكتالوج أولاً (load_seed_data.py)")

        agents_client = AgentsClient(endpoint=endpoint, credential=DefaultAzureCredential())
        try:
            sync(agents_client, agent_id, md_files)
        finally:
            agents_client.close()

    print("تمت المزامنة بنجاح ✅")


if __name__ == "__main__":
    main()
