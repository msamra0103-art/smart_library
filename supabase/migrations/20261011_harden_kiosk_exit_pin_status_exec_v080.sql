revoke execute on function public.kiosk_exit_pin_status(uuid) from public, anon;
grant execute on function public.kiosk_exit_pin_status(uuid) to authenticated, service_role;
