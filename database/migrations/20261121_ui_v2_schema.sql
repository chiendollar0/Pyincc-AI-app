-- Forward-only idempotent migration: UI v2 fields (tenant specialty, price-free catalog group_label/active, booking follow_up_due)

alter table public.organizations
  add column if not exists specialty text;

alter table public.catalog_items
  add column if not exists group_label text not null default 'Khác',
  add column if not exists active boolean not null default true;

update public.catalog_items
set group_label = case
  when category = 'eyebrow' then 'Chân mày'
  when category = 'lip' then 'Môi'
  else 'Khác'
end
where group_label = 'Khác' and category in ('eyebrow', 'lip');

alter table public.bookings
  add column if not exists follow_up_due date;
