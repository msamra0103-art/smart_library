## v0.6.9 — External Kiosk + Deployment Regression Fix

- PASS: app.js syntax checked with Node.
- PASS: active scanner handler no longer uses the 90ms early-submit rule.
- PASS: kiosk input stays programmatically blank while HID characters are collected.
- PASS: Enter/Tab suffix remains supported automatically; no physical Enter press is required from the student.
- PASS: fallback waits 350ms after the full scanner burst before submission.
- PASS: successful checkout resets the student session immediately.
- PASS: Vercel Hobby cron is now once daily at 03:00 UTC (06:00 Qatar), which satisfies Hobby limits.
- PASS: GitHub Actions adds the second keep-alive at 15:00 UTC (18:00 Qatar).
- ROOT CAUSE VERIFIED: the previous GitHub commit had Vercel status failure, so the scanner fixes in v0.6.8 were not live on smartlibrary-one.vercel.app.

# تقرير اختبار Bilal Smart Library v0.6 Production

## النتيجة العامة
تمت ترقية الواجهة وقاعدة Supabase إلى إصدار Production Hardening مع تحسين الأمان والتزامن والمحطات والاستيراد والحجز.

## فحوص الواجهة
- `app.js` اجتاز `node --check` بدون أخطاء Syntax.
- `index.html` مرتبط بملفات CSS وCloud Config وJavaScript بصورة صحيحة.
- رقم الإصدار موحد إلى `0.6.0`.
- قوالب Excel الجديدة تم إنشاؤها وفحص رؤوس الأعمدة باستخدام `artifact_tool`.

## قاعدة البيانات — تم تطبيقها فعليًا
- إضافة نوع المحطة `station_type`.
- ربط حساب Kiosk بمحطة محددة عبر `memberships.station_id`.
- منع ربط حسابي Kiosk نشطين بالمحطة نفسها.
- إضافة إعدادات الصوت، السماح بمسح الرقم الشخصي، ورمز خروج Kiosk المشفر.
- تشديد RLS بحيث لا يقرأ Kiosk/Viewer بيانات الطلاب الحساسة أو سجل العمليات مباشرة.
- تحسين RLS لإزالة تحذير إعادة حساب `auth.uid()` لكل صف.

## المعاملات والتزامن
- إنشاء دوال v2 محمية للاستعارة والإرجاع والتجديد والحجز والإلغاء.
- الاستعارة تقفل سجل الطالب ونسخة الكتاب أثناء المعاملة.
- يوجد Unique Index يمنع وجود استعارتين نشطتين لنفس النسخة.
- تم تشغيل Smoke Test حقيقي داخل Transaction على قاعدة Supabase:
  - إنشاء طالب وكتاب ونسخة مؤقتة.
  - استعارة ناجحة.
  - إرجاع ناجح.
  - Rollback كامل لبيانات الاختبار.
- النتيجة: `PASS v0.6 checkout/return transaction rollback smoke test`.

## الحجز
- إصلاح حالة حجز نسخة محددة ثم محاولة مسح نسخة أخرى من العنوان.
- تنظيف الحجوزات المنتهية آليًا.
- Cron Job باسم `library_reservation_cleanup_v06` يعمل كل 5 دقائق.
- عند انتهاء الحجز تنتقل النسخة إلى الطالب التالي أو تعود إلى متاح.

## Edge Functions
- `library-users` — الإصدار 4 ACTIVE:
  - كلمة مرور 8 أحرف على الأقل.
  - إنشاء/تعديل عدة مديرين وأمناء مكتبة.
  - حساب Kiosk يتطلب محطة مفعلة.
  - حماية آخر مدير نشط.
  - تعيين رمز خروج Kiosk.
- `library-transaction` — الإصدار 2 ACTIVE:
  - صلاحيات مختلفة حسب الدور.
  - Kiosk: lookup + checkout + return فقط.
  - Viewer Snapshot بدون الرقم الشخصي/RFID.
  - Heartbeat للمحطات.
  - التحقق من نوع المحطة قبل الاستعارة/الإرجاع.

## Realtime
تم تفعيل Supabase Realtime على 6 جداول تشغيلية:
- students
- books
- book_copies
- loans
- reservations
- stations

التحقق من القاعدة أعاد:
- Realtime tables = 6
- Cron cleanup jobs = 1
- authenticated direct execute on checkout RPC = false
- service_role execute on checkout RPC = true

## Supabase Advisors
بعد التعديلات:
- تم حل تحذيرات `auth_rls_initplan` التي أضيفت أثناء التشديد.
- تحذيرات `unused_index` فقط هي المتبقية في Performance Advisor، وهذا طبيعي في مشروع جديد قليل البيانات، لذلك لم نحذف الفهارس المهمة قبل وجود حمل فعلي.
- تمت إضافة سياسة رفض صريحة لجدول `bootstrap_tokens`؛ لم يعد يظهر تحذير RLS بدون Policy.
- التحذير الأمني الوحيد المتبقي هو أن **Leaked Password Protection** في Supabase Auth غير مفعلة؛ تفعيلها إعداد منصة مستقل في إعدادات Auth وليس تعديلًا في كود النظام.

## اختبار مادي مطلوب داخل المدرسة
لا يمكن توصيل قارئ USB فعلي من بيئة التطوير. قبل التوسع:
1. افتح **اختبار قارئ الباركود** من الإعدادات.
2. تأكد أن الجهاز يرسل Enter.
3. جرّب 5 بطاقات طلاب و5 ملصقات كتب.
4. جرّب جهازين في الوقت نفسه.
5. اختبر حساب Kiosk ومحطة الإرجاع وحساب المدير.

## v0.6.1 Kiosk Exit UX
- PASS: لا توجد استدعاءات `prompt()` لخروج المحطة.
- PASS: فحص JavaScript عبر `node --check`.
- PASS: أضيف RPC آمن `kiosk_exit_pin_status` يعيد حالة وجود PIN فقط دون كشف الـ hash.
- PASS: مسار بدون PIN = تأكيد داخلي ثم Sign Out إلى شاشة الدخول.
- PASS: مسار مع PIN = نموذج داخلي ثم `verify_exit_pin`.

## v0.6.3 — Return-date rendering regression

- Supabase verification: PASS — returned loans contain non-null `returned_at`.
- Front-end template fix: PASS — returned date now executes `formatISODate(...)` instead of displaying the JavaScript expression literally.
- JavaScript syntax check: PASS.

- v0.6.3: تم اختبار منطق الحركة اليومية، والتصفية حسب التاريخ ونوع العملية والبحث، وإظهار الاستعارة والإرجاع كسجلين مستقلين عند حدوثهما في اليوم نفسه.

## v0.6.4 — Supabase Keep-Alive
- تم إنشاء `public.keepalive_health` مع RLS ومنع القراءة المباشرة من `anon` و`authenticated`.
- تم إنشاء `public.keepalive_ping()` بصلاحية تنفيذ لـ `anon` و`authenticated` فقط.
- تم اختبار الدالة تحت دور `anon` ونجحت، وارتفع `ping_count` من 0 إلى 1.
- تمت إضافة Vercel Serverless Function في `api/keepalive.js`.
- تمت إضافة Vercel Cron يومي في `vercel.json`.
- لا يوجد `service_role` داخل ملفات الواجهة أو مسار Keep-Alive.


## v0.6.5 — External Kiosk Barcode + Session Lifecycle
- PASS: JavaScript syntax (`node --check`).
- PASS: Kiosk scanner path no longer rejects scans because another input element retained browser focus.
- PASS: HID terminators supported: Enter and Tab.
- PASS: duplicate-scan guard added for repeated CR/LF-style suffixes.
- PASS: successful checkout calls `resetKiosk()` immediately; no post-checkout countdown.
- PASS: Kiosk checkout skips a full cloud reload before returning to the ready screen.
- NOTE: physical USB reader validation still requires the actual school reader/browser combination.

### Automated scanner simulations
- PASS: simulated external Kiosk with browser focus deliberately left on a different hidden input; numeric barcode was captured successfully.
- PASS: second scan terminated by `Tab` was captured successfully.
- PASS: immediate repeated duplicate barcode was suppressed.
- PASS: simulated successful checkout reset the student session immediately and returned `state.kiosk.student` to null.


## v0.6.8 — Keep-Alive Schedule
- `vercel.json` valid JSON.
- Cron schedule: `0 3,15 * * *`.
- Expected Qatar times: ~06:00 and ~18:00 daily.


## v0.6.8 — External Kiosk Pre‑Login

- PASS: JavaScript syntax check (`node --check`).
- PASS: قاعدة البيانات تحتوي أعمدة Token/Activation للمحطات.
- PASS: `library-users` v5 يصدر كود تفعيل خارجي للمدير ويلغي الجهاز الخارجي.
- PASS: `library-public-kiosk` v1 منشورة مع `verify_jwt=false` ولكن بمصادقة Token مخصصة للمحطة وصلاحيات Kiosk محدودة.
- PASS: `checkout_book_v2` و`return_book_v2` يقبلان `p_actor_user_id = null` لتسجيل عملية محطة عامة بدون حساب إداري.
- PASS: واجهة Kiosk الخارجية تستخدم نفس ماسك HID المحسن لـ Enter/Tab وتغلق جلسة الطالب فور نجاح الاستعارة.
- ملاحظة: تعذر تنفيذ اختبار HTTP مباشر من بيئة البناء بسبب منع DNS الخارجي في الحاوية؛ تم تنظيف محطة الاختبار المؤقتة بالكامل بعد المحاولة.


## v0.6.8 scanner regression
- تمت مراجعة مسار محطة الاستعارة الخارجية بحيث لا يعتمد على Enter.
- إدخال القارئ السريع يُجمع في buffer ويُرسل تلقائيًا بعد 90ms من توقف الإدخال.
- حقل المسح أصبح readonly لمنع وميض رقم الطالب على الشاشة.
- ما زال Enter/Tab مدعومًا كخيار توافق، لكنه غير مطلوب.


## v0.7.1 Unified circulation test
تم اختبار دالة circulate_book_v3 داخل Transaction ثم Rollback: أول مسح للكتاب أنشأ checkout، والمسح التالي لنفس الطالب/النسخة أنشأ return، وأصبحت حالة النسخة available وحالة الاستعارة returned مع returned_at غير فارغ.

## v0.7.1 Keep-Alive package validation

- `.github/workflows/keepalive.yml` present.
- Schedule: `0 3 * * *` and `0 15 * * *` (06:00 / 18:00 Qatar).
- Manual `workflow_dispatch` present.
- Vercel Cron removed to remain compatible with Hobby plan.
- Workflow uses retries and validates an `ok:true` response.


## v0.7.2 checks
- Initial kiosk scan distinguishes student card vs on-loan book.
- On-loan book path calls return immediately with no student session required.
- Current KIOSK-01 configured as Hybrid in Supabase.
- JavaScript syntax and ZIP integrity checked.
