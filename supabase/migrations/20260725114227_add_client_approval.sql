-- اعتماد العميل (خارجي، بدون تسجيل دخول) عبر رابط المشاركة
-- الهدف: يخلّي "المراجع" في شركة العميل (أبو عوف) يعتمد الجلسة نهائيًا من
-- نفس صفحة /share/:token، من غير ما يحتاج حساب أو صلاحيات على الجداول.
-- التعديل نفسه بيتم عبر edge function (approve-session) بصلاحية service_role
-- بعد التحقق من share_token يدويًا — مفيش grant مباشر لـanon على UPDATE هنا
-- عن قصد، عشان محدش يقدر يعدّل البيانات مباشرة حتى لو عرف الرابط.
ALTER TABLE public.reconciliation_sessions
  ADD COLUMN client_approved_at TIMESTAMPTZ,
  ADD COLUMN client_approved_by TEXT;
