-- 01_eda_and_data_profiling.sql
-- project: purchasing & inventory monitoring
-- eda va check data truoc khi dung view

-- 1. kiem tra schema va so luong dong cac bang chinh
select table_schema, table_name
from information_schema.tables
where table_schema in ('purchasing', 'warehouse')
order by table_schema, table_name;

select 'purchasing.suppliers' as table_name, count(*) as total_rows from purchasing.suppliers
union all 
select 'purchasing.purchase_orders', count(*) from purchasing.purchase_orders
union all 
select 'purchasing.purchase_order_lines', count(*) from purchasing.purchase_order_lines
union all 
select 'warehouse.stock_items', count(*) from warehouse.stock_items 
union all 
select 'warehouse.stock_item_holdings', count(*) from warehouse.stock_item_holdings;

-- 2. tim moc ngay chan (anchor date) de tinh toan
-- ngay dat cuoi cung la 2016-05-31
select 
    min(order_date) as min_order_date,
    max(order_date) as max_order_date,
    min(expected_delivery_date) as min_expected_date,
    max(expected_delivery_date) as max_expected_date
from purchasing.purchase_orders;

-- 3. check tinh trang giao nhan cua cac dong PO
select 
    is_order_line_finalized,
    count(*) as total_lines,
    min(last_receipt_date) as min_receipt_date,
    max(last_receipt_date) as max_receipt_date,
    sum(case when coalesce(received_outers, 0) < ordered_outers then 1 else 0 end) as count_under_received,
    sum(case when received_outers = ordered_outers then 1 else 0 end) as count_exact_received,
    sum(case when received_outers > ordered_outers then 1 else 0 end) as count_over_received
from purchasing.purchase_order_lines 
group by is_order_line_finalized;

-- 4. xem chi tiet 9 dong don dang mo xem co bi qua han so voi ngay 2016-05-31 khong
select 
    po.purchase_order_id,
    s.supplier_name,
    po.order_date,
    po.expected_delivery_date,
    pol.ordered_outers,
    case 
        when po.expected_delivery_date < date '2016-05-31' then 'qua han'
        else 'trong han'
    end as delay_status
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
join purchasing.suppliers s on po.supplier_id = s.supplier_id
where pol.is_order_line_finalized = false;

-- 5. tinh ty le giao dung han (otd) trong qua khu
select 
    count(*) as total_finalized_lines,
    sum(case when pol.last_receipt_date <= po.expected_delivery_date then 1 else 0 end) as on_time_lines,
    sum(case when pol.last_receipt_date > po.expected_delivery_date then 1 else 0 end) as late_lines,
    round(100.0 * sum(case when pol.last_receipt_date <= po.expected_delivery_date then 1 else 0 end) / count(*), 2) as otd_percentage
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
where pol.is_order_line_finalized = true;

-- 6. phan loai trang thai ton kho
select 
    count(*) as total_items,
    sum(case when quantity_on_hand <= 0 then 1 else 0 end) as out_of_stock_count,
    sum(case when quantity_on_hand > 0 and quantity_on_hand <= reorder_level then 1 else 0 end) as understocked_count,
    sum(case when quantity_on_hand > reorder_level and quantity_on_hand <= target_stock_level then 1 else 0 end) as optimal_stock_count,
    sum(case when quantity_on_hand > target_stock_level then 1 else 0 end) as overstocked_count,
    min(quantity_on_hand) as min_qty_on_hand,
    max(quantity_on_hand) as max_qty_on_hand
from warehouse.stock_item_holdings;

-- 7. xem 2 san pham bi thieu hang (understocked)
select 
    si.stock_item_name,
    sih.quantity_on_hand,
    sih.reorder_level,
    sih.target_stock_level,
    sih.last_cost_price
from warehouse.stock_item_holdings sih
join warehouse.stock_items si on sih.stock_item_id = si.stock_item_id
where sih.quantity_on_hand <= sih.reorder_level;

-- 8. top 5 san pham ton kho nhieu nhat
select 
    si.stock_item_name,
    sih.quantity_on_hand,
    sih.target_stock_level,
    sih.last_cost_price,
    round((sih.quantity_on_hand * sih.last_cost_price)::numeric, 2) as total_holding_value
from warehouse.stock_item_holdings sih
join warehouse.stock_items si on sih.stock_item_id = si.stock_item_id
order by sih.quantity_on_hand desc
limit 5;

-- 9. check du lieu bien: he so dong goi co hop le khong (> 0)
select 
    count(*) as total_skus,
    sum(case when quantity_per_outer is null or quantity_per_outer <= 0 then 1 else 0 end) as invalid_conversion_count,
    min(quantity_per_outer) as min_qty_per_outer,
    max(quantity_per_outer) as max_qty_per_outer
from warehouse.stock_items;

-- 10. check thoi gian giao hang (lead time ngay)
select 
    min(pol.last_receipt_date - po.order_date) as min_delivery_days,
    max(pol.last_receipt_date - po.order_date) as max_delivery_days,
    round(avg(pol.last_receipt_date - po.order_date), 1) as avg_delivery_days,
    sum(case when pol.last_receipt_date < po.order_date then 1 else 0 end) as invalid_negative_lead_time_count
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
where pol.is_order_line_finalized = true;