do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.gc_get_my_member_profile()'::regprocedure);
  v_new := replace(v_def,
    'if coalesce(pr.is_disabled,false) or not coalesce(pr.is_active,true) then',
    'if not coalesce(pr.mobile_verified,false) or upper(coalesce(pr.mobile_verification_status,'''') )<>''VERIFIED'' then raise exception ''Your mobile number is awaiting GURU CONNECT Verification Team confirmation. Login access will be enabled only after verification.''; end if; if coalesce(pr.is_disabled,false) or not coalesce(pr.is_active,true) then');
  v_new := replace(v_new,
    'if coalesce(st.is_disabled,false) or not coalesce(st.registration_approved,false) or upper(coalesce(st.registration_approval_status,''''))<>''APPROVED'' then',
    'if not coalesce(st.mobile_verified,false) or upper(coalesce(st.mobile_verification_status,''''))<>''VERIFIED'' then raise exception ''Your mobile number is awaiting GURU CONNECT Verification Team confirmation.''; end if; if coalesce(st.is_disabled,false) or not coalesce(st.registration_approved,false) or upper(coalesce(st.registration_approval_status,''''))<>''APPROVED'' then');
  v_new := replace(v_new,
    'if coalesce(tr.is_disabled,false) or not coalesce(tr.registration_approved,false) or upper(coalesce(tr.registration_approval_status,''''))<>''APPROVED'' then',
    'if not coalesce(tr.mobile_verified,false) or upper(coalesce(tr.mobile_verification_status,''''))<>''VERIFIED'' then raise exception ''Your mobile number is awaiting GURU CONNECT Verification Team confirmation.''; end if; if coalesce(tr.is_disabled,false) or not coalesce(tr.registration_approved,false) or upper(coalesce(tr.registration_approval_status,''''))<>''APPROVED'' then');
  if v_new = v_def then
    raise exception 'Could not locate the expected member-access checks; no function changes applied.';
  end if;
  execute v_new;
end $$;

do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.gc_store_create_order(uuid[])'::regprocedure);
  v_new := replace(v_def,
    'and upper(coalesce(p.registration_approval_status,''APPROVED''))=''APPROVED'';',
    'and upper(coalesce(p.registration_approval_status,''APPROVED''))=''APPROVED'' and coalesce(p.mobile_verified,false) is true;');
  if v_new = v_def then
    raise exception 'Could not locate the expected store-order approval check; no function changes applied.';
  end if;
  execute v_new;
end $$;