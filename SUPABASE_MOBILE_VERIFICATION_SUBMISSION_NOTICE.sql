create or replace function public.gc_notify_admin_new_registration()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if lower(coalesce(new.role,'')) in ('student','tutor')
     and upper(coalesce(new.registration_approval_status,'')) <> 'APPROVED'
     and coalesce(new.registration_approved,false)=false
     and exists (
       select 1 from public.gc_registration_submissions g
       where g.auth_user_id=new.id
     ) then
    insert into public.gc_admin_notifications(user_id,member_role,title,body)
    values (
      new.id,
      lower(new.role),
      'New ' || initcap(lower(new.role)) || ' Registration Pending',
      coalesce(new.full_name,'A new member') || ' submitted a registration form and is awaiting Admin approval and mobile verification.'
    );
  end if;
  return new;
end;
$function$;