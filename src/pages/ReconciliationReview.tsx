import { useEffect, useMemo, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { AppLayout } from "@/components/AppLayout";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { TransformWrapper, TransformComponent } from "react-zoom-pan-pinch";
import { ChevronRight, ChevronLeft, CheckCircle2, AlertTriangle, HelpCircle, XCircle, RefreshCw, Share2, Download } from "lucide-react";
import { toast } from "@/hooks/use-toast";

interface Page {
  id: string;
  page_index: number;
  receipt_code: string;
  image_path: string;
  branch: string | null;
  receipt_date: string | null;
  supplier: string | null;
  invoice_number: string | null;
  review_status: string;
  reviewer_note: string | null;
  extraction_status: string;
  extraction_error: string | null;
}

interface Item {
  id: string;
  item_index: number;
  item_code: string;
  description: string;
  unit: string | null;
  quantity: number | null;
  unit_price: number | null;
  total: number | null;
  match_status: string;
  reviewer_note: string | null;
}

const STATUS_LABELS: Record<string, { label: string; color: string; Icon: any }> = {
  confirmed: { label: "مؤكد", color: "bg-green-500/15 text-green-700 dark:text-green-400 border-green-500/30", Icon: CheckCircle2 },
  partial: { label: "مؤكد جزئياً", color: "bg-amber-500/15 text-amber-700 dark:text-amber-400 border-amber-500/30", Icon: AlertTriangle },
  needs_review: { label: "يحتاج مراجعة", color: "bg-orange-500/15 text-orange-700 dark:text-orange-400 border-orange-500/30", Icon: HelpCircle },
  not_in_receipt: { label: "غير موجود بالإذن", color: "bg-red-500/15 text-red-700 dark:text-red-400 border-red-500/30", Icon: XCircle },
  unmatched: { label: "بدون مطابقة", color: "bg-muted text-muted-foreground border-muted", Icon: HelpCircle },
};

export default function ReconciliationReview() {
  const { id } = useParams();
  const [session, setSession] = useState<any>(null);
  const [pages, setPages] = useState<Page[]>([]);
  const [items, setItems] = useState<Item[]>([]);
  const [currentIdx, setCurrentIdx] = useState(0);
  const [imgUrl, setImgUrl] = useState<string | null>(null);
  const [reExtracting, setReExtracting] = useState(false);

  const currentPage = pages[currentIdx];
  const pageItems = useMemo(
    () => items.filter((it) => currentPage && it["page_id" as keyof Item] === (currentPage.id as any))
      .sort((a, b) => a.item_index - b.item_index),
    [items, currentPage],
  );

  const refresh = async () => {
    if (!id) return;
    const [{ data: s }, { data: p }, { data: it }] = await Promise.all([
      (supabase as any).from("reconciliation_sessions").select("*").eq("id", id).single(),
      (supabase as any).from("receipt_pages").select("*").eq("session_id", id).order("page_index"),
      (supabase as any).from("receipt_items").select("*").eq("session_id", id),
    ]);
    setSession(s);
    setPages(p ?? []);
    setItems(it ?? []);
  };

  useEffect(() => { refresh(); }, [id]);

  useEffect(() => {
    if (!currentPage) { setImgUrl(null); return; }
    (async () => {
      const { data } = await supabase.storage
        .from("maintenance-receipts")
        .createSignedUrl(currentPage.image_path, 3600);
      setImgUrl(data?.signedUrl ?? null);
    })();
  }, [currentPage?.id]);

  const setPageStatus = async (status: string) => {
    if (!currentPage) return;
    await (supabase as any).from("receipt_pages").update({ review_status: status }).eq("id", currentPage.id);
    refresh();
  };

  const setItemStatus = async (itemId: string, status: string) => {
    await (supabase as any).from("receipt_items").update({ match_status: status }).eq("id", itemId);
    refresh();
  };

  const goNext = () => setCurrentIdx((i) => Math.min(pages.length - 1, i + 1));
  const goPrev = () => setCurrentIdx((i) => Math.max(0, i - 1));

  // أهم ميزة للسرعة: معظم الأذون بتتطابق صح من أول مرة، فبدل ما تضغط على كل
  // بند لوحده، ضغطة واحدة تأكّد كل بنود الإذن الحالي + الإذن نفسه، وتنقل
  // تلقائيًا للي بعده — نفس فكرة "swipe to approve" في تطبيقات المراجعة السريعة.
  const confirmAllAndNext = async () => {
    if (!currentPage) return;
    const ids = pageItems.map((it) => it.id);
    if (ids.length) {
      await (supabase as any).from("receipt_items").update({ match_status: "confirmed" }).in("id", ids);
    }
    await (supabase as any).from("receipt_pages").update({ review_status: "confirmed" }).eq("id", currentPage.id);
    await refresh();
    goNext();
  };

  const flagAndNext = async () => {
    if (!currentPage) return;
    await (supabase as any).from("receipt_pages").update({ review_status: "needs_review" }).eq("id", currentPage.id);
    await refresh();
    goNext();
  };

  // اختصارات كيبورد: Enter/C = تأكيد الكل والتالي، F = تعليم يحتاج مراجعة والتالي،
  // الأسهم = تنقل بدون تغيير حالة. بتوفر وقت كبير على دفعات كبيرة من الأذون.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "TEXTAREA" || tag === "INPUT") return; // ما تتعارضش مع الكتابة في الملاحظات
      if (e.key === "Enter" || e.key.toLowerCase() === "c") {
        e.preventDefault();
        confirmAllAndNext();
      } else if (e.key.toLowerCase() === "f") {
        e.preventDefault();
        flagAndNext();
      } else if (e.key === "ArrowLeft") {
        goNext(); // في RTL: يسار = التالي بصريًا
      } else if (e.key === "ArrowRight") {
        goPrev();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentPage, pageItems]);


  const reExtract = async () => {
    if (!currentPage) return;
    setReExtracting(true);
    try {
      const { error } = await supabase.functions.invoke("foundry-extract-receipt", { body: { pageId: currentPage.id } });
      if (error) throw error;
      toast({ title: "تم الاستخراج", description: "أعيد قراءة الإذن" });
      await refresh();
    } catch (e: any) {
      toast({ title: "فشل الاستخراج", description: e.message, variant: "destructive" });
    } finally {
      setReExtracting(false);
    }
  };

  const shareLink = async () => {
    if (!session) return;
    await (supabase as any).from("reconciliation_sessions").update({ is_public: true }).eq("id", session.id);
    const url = `${window.location.origin}/share/${session.share_token}`;
    await navigator.clipboard.writeText(url);
    toast({ title: "تم نسخ الرابط", description: url });
    refresh();
  };

  if (!session) return <AppLayout><div className="p-6" dir="rtl">جارٍ التحميل...</div></AppLayout>;
  if (!pages.length) return <AppLayout><div className="p-6" dir="rtl">لا توجد صفحات في هذه الجلسة.</div></AppLayout>;

  return (
    <AppLayout>
      <div className="h-[calc(100vh-3rem)] flex flex-col" dir="rtl">
        {/* Header */}
        <div className="border-b p-3 flex items-center justify-between gap-3 flex-wrap bg-card">
          <div className="flex items-center gap-3 flex-wrap">
            <h2 className="font-bold">{session.name}</h2>
            <span className="text-sm px-2 py-0.5 rounded bg-muted">
              إذن <b>{currentPage?.receipt_code}</b>
            </span>
            {currentPage?.branch && <span className="text-sm text-muted-foreground">الفرع: {currentPage.branch}</span>}
            {currentPage?.receipt_date && <span className="text-sm text-muted-foreground">التاريخ: {currentPage.receipt_date}</span>}
            <span className="text-sm text-muted-foreground">البنود: {pageItems.length}</span>
          </div>
          <div className="flex items-center gap-2">
            <Button size="sm" onClick={confirmAllAndNext} className="font-bold">
              <CheckCircle2 className="h-4 w-4 ml-1" />
              تأكيد الكل والتالي
              <kbd className="mr-2 text-[10px] px-1 rounded bg-primary-foreground/20">Enter</kbd>
            </Button>
            <Button variant="outline" size="sm" onClick={flagAndNext}>
              <HelpCircle className="h-4 w-4 ml-1" />
              يحتاج مراجعة والتالي
              <kbd className="mr-2 text-[10px] px-1 rounded bg-muted">F</kbd>
            </Button>
            <Button variant="outline" size="sm" onClick={reExtract} disabled={reExtracting}>
              <RefreshCw className={`h-4 w-4 ml-1 ${reExtracting ? "animate-spin" : ""}`} />
              إعادة استخراج
            </Button>
            <Button variant="outline" size="sm" onClick={shareLink}>
              <Share2 className="h-4 w-4 ml-1" />
              مشاركة
            </Button>
            <Button variant="outline" size="sm" asChild>
              <Link to={`/reconciliation/${id}/export`}>
                <Download className="h-4 w-4 ml-1" />
                تصدير / طباعة
              </Link>
            </Button>
          </div>
        </div>

        {/* شريط التقدم */}
        <div className="h-1.5 bg-muted">
          <div
            className="h-full bg-green-500 transition-all"
            style={{ width: `${pages.length ? (pages.filter((p) => p.review_status === "confirmed").length / pages.length) * 100 : 0}%` }}
          />
        </div>

        {/* Body: image + items */}
        <div className="flex-1 flex overflow-hidden">
          {/* Image (right in RTL = visual left) */}
          <div className="flex-1 bg-muted/40 border-l relative overflow-hidden">
            {imgUrl ? (
              <TransformWrapper minScale={0.3} initialScale={0.8} centerOnInit>
                <TransformComponent wrapperStyle={{ width: "100%", height: "100%" }}>
                  <img src={imgUrl} alt={currentPage?.receipt_code} className="max-w-full" />
                </TransformComponent>
              </TransformWrapper>
            ) : (
              <div className="flex items-center justify-center h-full text-muted-foreground">جارٍ تحميل الصورة...</div>
            )}
          </div>

          {/* Items panel */}
          <div className="w-[520px] overflow-auto p-3 space-y-2 bg-background">
            {currentPage?.extraction_status === "processing" && (
              <Card className="p-3 text-sm text-muted-foreground">جارٍ الاستخراج من الوكيل...</Card>
            )}
            {currentPage?.extraction_status === "failed" && (
              <Card className="p-3 text-sm border-destructive/50 bg-destructive/10">
                فشل الاستخراج: {currentPage.extraction_error}
              </Card>
            )}
            {pageItems.length === 0 && currentPage?.extraction_status === "done" && (
              <Card className="p-3 text-sm text-muted-foreground">لم يستخرج الوكيل أي بنود من هذا الإذن.</Card>
            )}
            {pageItems.map((it) => {
              const info = STATUS_LABELS[it.match_status] ?? STATUS_LABELS.unmatched;
              const Icon = info.Icon;
              return (
                <Card key={it.id} className="p-3 text-sm">
                  <div className="flex items-start justify-between gap-2 mb-1">
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-mono px-1.5 py-0.5 rounded bg-muted">{it.item_code}</span>
                        <span className={`text-xs px-1.5 py-0.5 rounded border inline-flex items-center gap-1 ${info.color}`}>
                          <Icon className="h-3 w-3" />
                          {info.label}
                        </span>
                      </div>
                      <p className="mt-1 font-medium">{it.description}</p>
                      <div className="mt-1 text-xs text-muted-foreground flex gap-3">
                        {it.unit && <span>الوحدة: {it.unit}</span>}
                        {it.quantity != null && <span>الكمية: {it.quantity}</span>}
                        {it.unit_price != null && <span>السعر: {it.unit_price}</span>}
                        {it.total != null && <span>الإجمالي: {it.total}</span>}
                      </div>
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-1 mt-2">
                    {Object.entries(STATUS_LABELS).filter(([k]) => k !== "unmatched").map(([k, v]) => (
                      <button
                        key={k}
                        onClick={() => setItemStatus(it.id, k)}
                        className={`text-xs px-2 py-0.5 rounded border ${it.match_status === k ? v.color : "border-muted hover:bg-muted"}`}
                      >
                        {v.label}
                      </button>
                    ))}
                  </div>
                </Card>
              );
            })}

            <Card className="p-3 bg-muted/30">
              <p className="text-xs font-semibold mb-2">حالة مراجعة هذا الإذن</p>
              <div className="flex flex-wrap gap-1">
                {[
                  ["confirmed", "مؤكد"],
                  ["needs_review", "يحتاج مراجعة"],
                  ["corrected", "تم التصحيح"],
                ].map(([k, l]) => (
                  <button
                    key={k}
                    onClick={() => setPageStatus(k)}
                    className={`text-xs px-2 py-1 rounded border ${currentPage?.review_status === k ? "bg-primary text-primary-foreground" : "hover:bg-muted"}`}
                  >
                    {l}
                  </button>
                ))}
              </div>
              <Textarea
                className="mt-2 text-xs"
                placeholder="ملاحظات المراجع..."
                defaultValue={currentPage?.reviewer_note ?? ""}
                onBlur={(e) =>
                  currentPage &&
                  (supabase as any).from("receipt_pages").update({ reviewer_note: e.target.value }).eq("id", currentPage.id)
                }
              />
            </Card>
          </div>
        </div>

        {/* Footer navigation */}
        <div className="border-t p-2 flex items-center justify-between bg-card">
          <Button variant="outline" size="sm" onClick={() => setCurrentIdx((i) => Math.max(0, i - 1))} disabled={currentIdx === 0}>
            <ChevronRight className="h-4 w-4 ml-1" />
            السابق
          </Button>
          <div className="flex items-center gap-2 text-sm">
            <span>الإذن {currentIdx + 1} من {pages.length}</span>
            <span className="text-xs text-green-700 dark:text-green-400">
              ({pages.filter((p) => p.review_status === "confirmed").length} مؤكد)
            </span>
            <select
              className="border rounded px-2 py-1 text-xs bg-background"
              value={currentIdx}
              onChange={(e) => setCurrentIdx(Number(e.target.value))}
            >
              {pages.map((p, i) => (
                <option key={p.id} value={i}>إذن {p.receipt_code}</option>
              ))}
            </select>
          </div>
          <Button variant="outline" size="sm" onClick={() => setCurrentIdx((i) => Math.min(pages.length - 1, i + 1))} disabled={currentIdx === pages.length - 1}>
            التالي
            <ChevronLeft className="h-4 w-4 mr-1" />
          </Button>
        </div>
      </div>
    </AppLayout>
  );
}
