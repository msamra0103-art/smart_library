alter table public.book_copies
  add column if not exists archived boolean not null default false;

create index if not exists book_copies_school_archived_idx
  on public.book_copies(school_id, archived);

create or replace function public.checkout_book_v2(
  p_school_id uuid,
  p_student_code text,
  p_book_code text,
  p_station_code text default null,
  p_method text default 'self',
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_student public.students%rowtype;
  v_copy public.book_copies%rowtype;
  v_book public.books%rowtype;
  v_settings public.library_settings%rowtype;
  v_station public.stations%rowtype;
  v_loan_id uuid;
  v_open_count integer;
  v_first_res public.reservations%rowtype;
  v_due timestamptz;
begin
  perform public.cleanup_expired_reservations_v2(p_school_id,p_actor_user_id);
  select * into v_student from public.students where school_id=p_school_id and (student_code=p_student_code or barcode=p_student_code or rfid_uid=p_student_code) and active=true limit 1 for update;
  if not found then raise exception 'student_not_found'; end if;
  select * into v_copy from public.book_copies where school_id=p_school_id and (copy_code=p_book_code or barcode=p_book_code or rfid_uid=p_book_code) limit 1 for update;
  if not found then raise exception 'book_copy_not_found'; end if;
  if coalesce(v_copy.archived,false) then raise exception 'book_copy_archived'; end if;
  if v_copy.status not in ('available','reserved') then raise exception 'book_copy_not_available'; end if;
  select * into v_book from public.books where id=v_copy.book_id and school_id=p_school_id and active=true;
  if not found then raise exception 'book_inactive_or_missing'; end if;
  select * into v_settings from public.library_settings where school_id=p_school_id;
  if not found then raise exception 'library_settings_missing'; end if;
  if v_settings.block_if_overdue and exists(select 1 from public.loans l where l.school_id=p_school_id and l.student_id=v_student.id and l.status='active' and l.returned_at is null and l.due_at<now()) then raise exception 'student_has_overdue_loans'; end if;
  select count(*) into v_open_count from public.loans l where l.school_id=p_school_id and l.student_id=v_student.id and l.status='active' and l.returned_at is null;
  if v_open_count>=v_settings.max_books then raise exception 'student_reached_loan_limit'; end if;
  select * into v_first_res from public.reservations r where r.school_id=p_school_id and r.book_id=v_copy.book_id and r.status in ('queued','ready') and (r.expires_at is null or r.expires_at>now()) order by case when r.status='ready' then 0 else 1 end,r.requested_at limit 1 for update;
  if found then
    if v_first_res.student_id<>v_student.id then raise exception 'book_reserved_for_another_student'; end if;
    if v_first_res.status='ready' and v_first_res.ready_copy_id is not null and v_first_res.ready_copy_id<>v_copy.id then raise exception 'reserved_copy_mismatch'; end if;
  end if;
  if p_station_code is not null then select * into v_station from public.stations where school_id=p_school_id and station_code=p_station_code and active=true; end if;
  v_due:=now()+make_interval(days=>v_settings.loan_days);
  insert into public.loans(school_id,student_id,book_copy_id,checkout_station_id,checkout_by,checkout_method,due_at)
  values(p_school_id,v_student.id,v_copy.id,v_station.id,p_actor_user_id,case when p_method in ('self','staff','import') then p_method else 'self' end,v_due)
  returning id into v_loan_id;
  update public.book_copies set status='on_loan',updated_at=now() where id=v_copy.id;
  if found then update public.reservations set status='fulfilled',fulfilled_at=now(),updated_at=now() where id=v_first_res.id; end if;
  insert into public.activity_logs(school_id,actor_user_id,station_id,student_id,book_copy_id,action,details)
  values(p_school_id,p_actor_user_id,v_station.id,v_student.id,v_copy.id,'checkout',jsonb_build_object('loan_id',v_loan_id,'method',p_method,'message',v_student.full_name||' ← '||v_book.title));
  return jsonb_build_object('ok',true,'loan_id',v_loan_id,'student_id',v_student.id,'student_name',v_student.full_name,'book_copy_id',v_copy.id,'book_title',v_book.title,'due_at',v_due);
end;
$$;

create or replace function public.circulate_book_v3(
  p_school_id uuid,
  p_student_code text,
  p_book_code text,
  p_station_code text default null,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_student public.students%rowtype;
  v_copy public.book_copies%rowtype;
  v_active_loan public.loans%rowtype;
  v_result jsonb;
begin
  perform public.cleanup_expired_reservations_v2(p_school_id,p_actor_user_id);
  select * into v_student from public.students where school_id=p_school_id and (student_code=p_student_code or barcode=p_student_code or rfid_uid=p_student_code) and active=true limit 1 for update;
  if not found then raise exception 'student_not_found'; end if;
  select * into v_copy from public.book_copies where school_id=p_school_id and (copy_code=p_book_code or barcode=p_book_code or rfid_uid=p_book_code) limit 1 for update;
  if not found then raise exception 'book_copy_not_found'; end if;
  if coalesce(v_copy.archived,false) then raise exception 'book_copy_archived'; end if;
  select * into v_active_loan from public.loans where school_id=p_school_id and book_copy_id=v_copy.id and status='active' and returned_at is null limit 1 for update;
  if found then
    if v_active_loan.student_id <> v_student.id then raise exception 'book_on_loan_to_another_student'; end if;
    v_result := public.return_book_v2(p_school_id,v_copy.copy_code,p_station_code,p_actor_user_id);
    return coalesce(v_result,'{}'::jsonb) || jsonb_build_object('operation','return','student_id',v_student.id,'student_name',v_student.full_name);
  end if;
  v_result := public.checkout_book_v2(p_school_id,v_student.student_code,v_copy.copy_code,p_station_code,'self',p_actor_user_id);
  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object('operation','checkout');
end;
$$;

create or replace function public.staff_checkout_book_v1(
  p_school_id uuid,
  p_student_code text,
  p_book_code text,
  p_station_code text default null,
  p_actor_user_id uuid default null,
  p_loan_days integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_result jsonb;
  v_loan_id uuid;
  v_due timestamptz;
  v_days integer;
begin
  if p_loan_days is not null and (p_loan_days < 1 or p_loan_days > 365) then raise exception 'invalid_loan_days'; end if;
  v_result := public.checkout_book_v2(p_school_id,p_student_code,p_book_code,p_station_code,'staff',p_actor_user_id);
  v_loan_id := (v_result->>'loan_id')::uuid;
  if p_loan_days is not null then
    v_days := p_loan_days;
    v_due := now() + make_interval(days=>v_days);
    update public.loans set due_at=v_due,updated_at=now() where id=v_loan_id and school_id=p_school_id;
  else
    select loan_days into v_days from public.library_settings where school_id=p_school_id;
    v_due := (v_result->>'due_at')::timestamptz;
  end if;
  update public.activity_logs set details=coalesce(details,'{}'::jsonb)||jsonb_build_object('loan_days',v_days,'due_at',v_due,'staff_checkout',true)
  where school_id=p_school_id and action='checkout' and details->>'loan_id'=v_loan_id::text;
  return v_result || jsonb_build_object('due_at',v_due,'loan_days',v_days,'method','staff');
end;
$$;

revoke all on function public.staff_checkout_book_v1(uuid,text,text,text,uuid,integer) from public, anon, authenticated;
grant execute on function public.staff_checkout_book_v1(uuid,text,text,text,uuid,integer) to service_role;
