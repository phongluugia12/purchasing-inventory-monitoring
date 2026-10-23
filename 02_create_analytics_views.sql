-- 02_create_analytics_views.sql
-- project: purchasing & inventory monitoring
-- muc dich: tao schema analytics va 4 view phuc vu bao cao power bi

-- 1. tao schema rieng cho tang analytics
create schema if not exists analytics;


-- 2. view dimension: bang ngay (date dimension)
-- pham vi: tu ngay dat hang dau tien den cuoi nam cua ngay dat hang cuoi cung
create or replace view analytics.vw_dim_date as
select
    d::date                                      as date_key,
    extract(year from d)::int                    as year,
    extract(quarter from d)::int                 as quarter,
    'Q' || extract(quarter from d)::int          as quarter_label,
    extract(month from d)::int                   as month_num,
    to_char(d, 'Month')                          as month_name,
    to_char(d, 'Mon')                            as month_short,
    to_char(d, 'YYYY-MM')                        as year_month,
    extract(week from d)::int                    as week_num,
    extract(isodow from d)::int                  as day_of_week,
    to_char(d, 'Day')                            as day_name,
    case when extract(isodow from d) <= 5 
         then true else false 
    end                                          as is_weekday
from generate_series(
    (select date_trunc('year', min(order_date)) from purchasing.purchase_orders),
    (select date_trunc('year', max(order_date)) + interval '1 year' - interval '1 day' from purchasing.purchase_orders),
    interval '1 day'
) as d;


-- 3. view dimension: danh muc san pham & nha cung cap
create or replace view analytics.vw_dim_stock_items as 
select 
    si.stock_item_id,
    si.stock_item_name,
    si.supplier_id,
    s.supplier_name,
    si.unit_package_id,
    si.outer_package_id,
    si.quantity_per_outer,
    si.lead_time_days as stated_lead_time_days,
    si.tax_rate,
    si.unit_price,
    si.recommended_retail_price,
    si.typical_weight_per_unit
from warehouse.stock_items si 
join purchasing.suppliers s on si.supplier_id = s.supplier_id;


-- 4. view fact: chi tiet don mua hang (purchasing)
create or replace view analytics.vw_fact_purchase_order_lines as
select 
    pol.purchase_order_line_id,
    pol.purchase_order_id,
    po.supplier_id,
    pol.stock_item_id,
    po.order_date,
    po.expected_delivery_date,
    pol.last_receipt_date,
    pol.ordered_outers,
    pol.received_outers,
    si.quantity_per_outer,
    -- quy doi sang so luong chiec co so
    (pol.ordered_outers * si.quantity_per_outer) as ordered_quantity,
    (coalesce(pol.received_outers, 0) * si.quantity_per_outer) as received_quantity,
    pol.expected_unit_price_per_outer,
    -- tong gia tri cam ket mua hang
    (pol.ordered_outers * pol.expected_unit_price_per_outer) as line_ordered_amount,
    po.is_order_finalized,
    pol.is_order_line_finalized,
    -- thoi gian giao hang thuc te (so ngay tu luc dat toi luc nhan)
    case 
        when pol.last_receipt_date is not null then (pol.last_receipt_date - po.order_date)
        else null 
    end as actual_lead_time_days,
    -- trang thai giao nhan dua tren moc ngay neo 2016-05-31
    case
        when pol.is_order_line_finalized = true then 'Completed'
        when po.expected_delivery_date < date '2016-05-31' and pol.is_order_line_finalized = false then 'Missed date'
        else 'Still in date'
    end as delivery_status,
    -- co giao hang dung hen (1 la dung/som, 0 la tre, null la chua nhan)
    case 
        when pol.last_receipt_date is not null and pol.last_receipt_date <= po.expected_delivery_date then 1 
        when pol.last_receipt_date is not null and pol.last_receipt_date > po.expected_delivery_date then 0
        else null
    end as is_delivery_on_time
from purchasing.purchase_order_lines pol 
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
join warehouse.stock_items si on pol.stock_item_id = si.stock_item_id;


-- 5. view fact: anh chup trang thai ton kho (inventory snapshot)
create or replace view analytics.vw_fact_inventory_snapshot as
select
    sih.stock_item_id,
    si.stock_item_name,
    si.supplier_id,
    sih.bin_location,
    sih.quantity_on_hand,
    sih.last_cost_price,
    -- tong gia tri von ton kho cua tung sku
    round((sih.quantity_on_hand * sih.last_cost_price)::numeric, 2) as total_inventory_valuation,
    sih.reorder_level,
    sih.target_stock_level,
    -- phan loai suc khoe ton kho dua tren cac nguong dinh muc
    case
        when sih.quantity_on_hand <= 0 then 'Out of stock'
        when sih.quantity_on_hand <= sih.reorder_level then 'Understocked'
        when sih.quantity_on_hand > sih.target_stock_level then 'Overstocked'
        else 'Optimal'
    end as inventory_health_status,
    -- so luong can dat bo sung de dua ton kho ve muc target
    greatest(0, (sih.target_stock_level - sih.quantity_on_hand)) as units_to_reorder 
from warehouse.stock_item_holdings sih 
join warehouse.stock_items si on sih.stock_item_id = si.stock_item_id;


-- 6. kiem tra nhanh so luong ban ghi sau khi khoi tao view
select 'dim_date' as view_name, count(*) as total_rows from analytics.vw_dim_date
union all
select 'dim_stock_items', count(*) from analytics.vw_dim_stock_items
union all
select 'fact_purchase_order_lines', count(*) from analytics.vw_fact_purchase_order_lines
union all
select 'fact_inventory_snapshot', count(*) from analytics.vw_fact_inventory_snapshot;