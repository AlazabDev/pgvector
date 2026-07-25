import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { TransformWrapper, TransformComponent } from "react-zoom-pan-pinch";
import { CheckCircle2, AlertTriangle, HelpCircle, XCircle, Download, ShieldCheck } from "lucide-react";
import { downloadReconciliationExcel } from "@/lib/exportExcel";
import { toast } from "@/hooks/use-toast";

const STATUS: Record<string, { label: string; color: string; Icon: any }> = {
  confirmed: { label: "مؤكد", color: "text-green-700 dark:text-green-400", Icon: CheckCircle2 },
  partial: { label: "مؤكد جزئياً", color: "text-amber-700 dark:text-amber-400", Icon: AlertTriangle },
  needs_review: { label: "يحتاج مراجعة", color: "text-orange-700 dark:text-orange-400", Icon: HelpCircle },
  not_in_receipt: { label: "غير موجود بالإذن", color: "text-red-700 dark:text-red-400", Icon: XCircle },
  unmatched: { label: "—", color: "text-muted-foreground", Icon: HelpCircle },
};

// دفتر المراجعة الخارجي: الهدف إن المراجع عند العميل (أبو عوف) يقدر يعتمد
// الجلسة كلها بضغطة واحدة من غير ما يحتاج يقرا كل بند بند — المراجعة
// التفصيلية بالفعل تمت من فريق الصيانة الداخلي (az-agent-maint + ReconciliationReview).
// دور المراجع هنا: نظرة سريعة على ملخص الحالة + استثناءات لو فيه، ثم اعتماد.
export default function SharedReview() {
  const { token } = useParams();
  const [session, setSession] = useState<any>(null);
  const [notFound, setNotFound] = useState(false);
  const [pages, setPages] = useState<any[]>([]);
  const [items, setItems] = useState<any[]>([]);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [reviewerName, setReviewerName] = useState("");
  const [approving, setApproving] = useState(false);

  const load = async () => {
    if (!token) return;
    const { data: s } = await (supabase as any)
      .from("reconciliation_sessions")
      .select("*")
      .eq("share_token", token)
      .eq("is_public", true)
      .maybeSingle();
    if (!s) { setNotFound(true); return; }
    setSession(s);
    const [{ data: p }, { data: it }] = await Promise.all([
      (supabase as any).from("receipt_pages").select("*").eq("session_id", s.id).order("page_index"),
      (supabase as any).from("receipt_items").select("*").eq("session_id", s.id),
    ]);
    setPages(p ?? []);
    setItems(it ?? []);
    const map: Record<string, string> = {};
    for (const pg of p ?? []) {
      const { data } = await supabase.storage.from("maintenance-receipts").createSignedUrl(pg.image_path, 3600);
      if (data?.signedUrl) map[pg.id] = data.signedUrl;
    }
    setUrls(map);
  };

  useEffect(() => { load(); }, [token]);

  const needsAttentionPages = pages.filter((p) => p.review_status !== "confirmed");
  const summary = {
    total: pages.length,
    confirmed: pages.filter((p) => p.review_status === "confirmed").length,
    needsAttention: needsAttentionPages.length,
  };

  const approve = async () => {
    if (!reviewerName.trim()) {
      toast({ title: "اكتب اسمك أولاً", variant: "destructive" });
      return;
    }
    setApproving(true);
    try {
      const { data, error } = await supabase.functions.invoke("approve-session", {
        body: { shareToken: token, reviewerName: reviewerName.trim() },
      });
      if (error) throw error;
      toast({
        title: data?.alreadyApproved ? "الجلسة معتمدة بالفعل" : "تم الاعتماد بنجاح ✅",
        description: data?.approvedBy ? `بواسطة ${data.approvedBy}` : undefined,
      });
      await load();
    } catch (e: any) {
      toast({ title: "فشل الاعتماد", description: e.message, variant: "destructive" });
    } finally {
      setApproving(false);
    }
  };

  if (notFound) return <div className="p-8 text-center" dir="rtl">الرابط غير صالح أو غير مفعّل.</div>;
  if (!session) return <div className="p-8 text-center" dir="rtl">جارٍ التحميل...</div>;

  const isApproved = Boolean(session.client_approved_at);

  return (
    <div className="min-h-screen bg-background" dir="rtl">
      <header className="border-b p-4 bg-card flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 className="text-xl font-bold">{session.name}</h1>
          <p className="text-sm text-muted-foreground">
            {session.branch ?? ""} {session.session_date ? `- ${session.session_date}` : ""} — دفتر مراجعة للاعتماد
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => downloadReconciliationExcel(session.name, pages, items)}
        >
          <Download className="h-4 w-4 ml-1" />
          تحميل Excel
        </Button>
      </header>

      {/* شريط الاعتماد السريع — أول حاجة يشوفها المراجع، من غير سكرول */}
      <div className="max-w-7xl mx-auto p-4">
        {isApproved ? (
          <Card className="p-4 bg-green-500/10 border-green-500/30 flex items-center gap-3">
            <ShieldCheck className="h-6 w-6 text-green-600 shrink-0" />
            <div>
              <p className="font-bold text-green-700 dark:text-green-400">تم اعتماد هذه المراجعة نهائيًا</p>
              <p className="text-sm text-muted-foreground">
                بواسطة {session.client_approved_by} — {new Date(session.client_approved_at).toLocaleString("ar-EG")}
              </p>
            </div>
          </Card>
        ) : (
          <Card className="p-4">
            <div className="flex flex-wrap items-center gap-4">
              <div className="flex gap-4 text-sm">
                <span>إجمالي الأذون: <b>{summary.total}</b></span>
                <span className="text-green-700 dark:text-green-400">مؤكد: <b>{summary.confirmed}</b></span>
                {summary.needsAttention > 0 && (
                  <span className="text-orange-700 dark:text-orange-400">يحتاج انتباه: <b>{summary.needsAttention}</b></span>
                )}
              </div>
              {summary.needsAttention > 0 && (
                <a href="#needs-attention" className="text-sm underline text-orange-700 dark:text-orange-400">
                  عرض الأذون اللي محتاجة انتباه ↓
                </a>
              )}
              <div className="flex items-center gap-2 mr-auto">
                <Input
                  placeholder="اسمك (للاعتماد)"
                  value={reviewerName}
                  onChange={(e) => setReviewerName(e.target.value)}
                  className="w-48"
                />
                <Button onClick={approve} disabled={approving}>
                  <ShieldCheck className="h-4 w-4 ml-1" />
                  {approving ? "جارٍ الاعتماد..." : "اعتماد المراجعة نهائيًا"}
                </Button>
              </div>
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              الاعتماد يعني موافقتك على كل البنود كما هي موضحة أدناه. تقدر تفتح أي إذن وتشوف صورته وبنوده بالتفصيل قبل ما تعتمد.
            </p>
          </Card>
        )}
      </div>

      <div id="needs-attention" className="max-w-7xl mx-auto px-4 space-y-6 pb-10">
        {pages.map((pg, idx) => {
          const pageItems = items.filter((it) => it.page_id === pg.id).sort((a, b) => a.item_index - b.item_index);
          return (
            <Card key={pg.id} className="overflow-hidden">
              <div className="border-b p-3 flex flex-wrap gap-4 items-center bg-muted/40">
                <b>إذن {pg.receipt_code}</b>
                {pg.branch && <span className="text-sm">الفرع: {pg.branch}</span>}
                {pg.receipt_date && <span className="text-sm">التاريخ: {pg.receipt_date}</span>}
                <span className="text-sm text-muted-foreground">البنود: {pageItems.length}</span>
                <span className={`text-sm ${pg.review_status === "confirmed" ? "text-green-700 dark:text-green-400" : "text-orange-700 dark:text-orange-400"}`}>
                  {pg.review_status === "confirmed" ? "مؤكد" : pg.review_status === "corrected" ? "تم التصحيح" : "يحتاج انتباه"}
                </span>
                <span className="text-sm mr-auto">({idx + 1} من {pages.length})</span>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2">
                <div className="border-l bg-muted/20 h-[600px]">
                  {urls[pg.id] && (
                    <TransformWrapper minScale={0.3} initialScale={0.7} centerOnInit>
                      <TransformComponent wrapperStyle={{ width: "100%", height: "100%" }}>
                        <img src={urls[pg.id]} alt={pg.receipt_code} />
                      </TransformComponent>
                    </TransformWrapper>
                  )}
                </div>
                <div className="p-3 overflow-auto max-h-[600px]">
                  <table className="w-full text-sm">
                    <thead className="text-xs text-muted-foreground border-b">
                      <tr>
                        <th className="text-right p-1">الكود</th>
                        <th className="text-right p-1">الوصف</th>
                        <th className="text-right p-1">كمية</th>
                        <th className="text-right p-1">الحالة</th>
                      </tr>
                    </thead>
                    <tbody>
                      {pageItems.map((it) => {
                        const info = STATUS[it.match_status] ?? STATUS.unmatched;
                        const Icon = info.Icon;
                        return (
                          <tr key={it.id} className="border-b">
                            <td className="p-1 font-mono text-xs">{it.item_code}</td>
                            <td className="p-1">{it.description}</td>
                            <td className="p-1">{it.quantity ?? "—"}</td>
                            <td className={`p-1 ${info.color}`}>
                              <span className="inline-flex items-center gap-1">
                                <Icon className="h-3 w-3" />
                                {info.label}
                              </span>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                  {pg.reviewer_note && (
                    <p className="mt-3 text-xs bg-muted p-2 rounded">ملاحظة: {pg.reviewer_note}</p>
                  )}
                </div>
              </div>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
