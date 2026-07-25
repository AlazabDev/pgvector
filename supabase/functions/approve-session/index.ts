// Edge function: يسمح لصاحب رابط المشاركة (المراجع عند العميل، بدون تسجيل
// دخول) باعتماد الجلسة نهائيًا. التحقق من share_token يتم هنا بصلاحية
// service_role (بعد التحقق اليدوي)، عشان مفيش داعي نمنح anon أي صلاحية
// UPDATE مباشرة على الجداول من الـRLS نفسها — كل التعديل يمر من هنا فقط.
import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'npm:@supabase/supabase-js@2';

interface ApproveRequest {
  shareToken: string;
  reviewerName: string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { shareToken, reviewerName } = (await req.json()) as ApproveRequest;

    if (!shareToken || !reviewerName || !reviewerName.trim()) {
      return new Response(
        JSON.stringify({ error: 'shareToken و reviewerName مطلوبين' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // نتحقق إن الرابط ده فعلاً جلسة عامة مفعّلة، ونجيب حالتها الحالية
    const { data: session, error: fetchError } = await supabase
      .from('reconciliation_sessions')
      .select('id, name, client_approved_at, client_approved_by')
      .eq('share_token', shareToken)
      .eq('is_public', true)
      .maybeSingle();

    if (fetchError) throw fetchError;
    if (!session) {
      return new Response(
        JSON.stringify({ error: 'الرابط غير صالح أو غير مفعّل' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (session.client_approved_at) {
      // اعتماد سابق موجود بالفعل — نرجّعه بدل ما نعتمد فوق بعض بصمت
      return new Response(
        JSON.stringify({
          alreadyApproved: true,
          approvedAt: session.client_approved_at,
          approvedBy: session.client_approved_by,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const approvedAt = new Date().toISOString();
    const { error: updateError } = await supabase
      .from('reconciliation_sessions')
      .update({ client_approved_at: approvedAt, client_approved_by: reviewerName.trim() })
      .eq('id', session.id);

    if (updateError) throw updateError;

    return new Response(
      JSON.stringify({ alreadyApproved: false, approvedAt, approvedBy: reviewerName.trim() }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error) {
    console.error('approve-session error:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'خطأ غير متوقع' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
