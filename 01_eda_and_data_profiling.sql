-- 01_eda_and_data_profiling.sql
-- Project: Purchasing & Inventory Monitoring
-- Purpose: Quick health check on raw data (row counts, date ranges, data quality) before building views.

-- 1. Check table names and row counts in purchasing and warehouse
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

-- 2. Check earliest and latest order dates (Anchor reporting date is 2016-05-31)
select
    min(order_date) as min_order_date,
    max(order_date) as max_order_date,
    min(expected_delivery_date) as min_expected_date,
    max(expected_delivery_date) as max_expected_date
from purchasing.purchase_orders;

-- 3. Check finished vs open order lines, and see if any line was under-received or over-received
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

-- 4. Check active open order lines that are still waiting for delivery (as of 2016-05-31)
select
    po.purchase_order_id,
    s.supplier_name,
    po.order_date,
    po.expected_delivery_date,
    pol.ordered_outers,
    case
        when po.expected_delivery_date < date '2016-05-31' then 'Missed date (Overdue)'
        else 'Still in date'
    end as delay_status
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
join purchasing.suppliers s on po.supplier_id = s.supplier_id
where po.is_order_finalized = false and pol.is_order_line_finalized = false;

-- 5. On-Time Delivery (OTD) rate: Did suppliers deliver on time?
-- Only evaluates finished orders that have both receipt date and expected delivery date.
-- Uses NULLIF to avoid divide-by-zero errors.
select
    count(*) as total_finalized_lines,
    count(case when pol.last_receipt_date is not null and po.expected_delivery_date is not null then 1 end) as evaluable_lines,
    sum(case when pol.last_receipt_date <= po.expected_delivery_date then 1 else 0 end) as on_time_lines,
    sum(case when pol.last_receipt_date > po.expected_delivery_date then 1 else 0 end) as late_lines,
    round(
        100.0 * sum(case when pol.last_receipt_date <= po.expected_delivery_date then 1 else 0 end)
        / nullif(count(case when pol.last_receipt_date is not null and po.expected_delivery_date is not null then 1 end), 0),
        2
    ) as otd_percentage
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
where pol.is_order_line_finalized = true;

-- 6. Check stock levels: Out of stock (<= 0), Low (<= reorder), Optimal, or Overstocked (> target)
select
    count(*) as total_items,
    sum(case when quantity_on_hand <= 0 then 1 else 0 end) as out_of_stock_count,
    sum(case when quantity_on_hand > 0 and quantity_on_hand <= reorder_level then 1 else 0 end) as understocked_count,
    sum(case when quantity_on_hand > reorder_level and quantity_on_hand <= target_stock_level then 1 else 0 end) as optimal_stock_count,
    sum(case when quantity_on_hand > target_stock_level then 1 else 0 end) as overstocked_count,
    min(quantity_on_hand) as min_qty_on_hand,
    max(quantity_on_hand) as max_qty_on_hand
from warehouse.stock_item_holdings;

-- 7. Find items running low on stock (understocked items that need reordering)
select
    si.stock_item_name,
    sih.quantity_on_hand,
    sih.reorder_level,
    sih.target_stock_level,
    sih.last_cost_price
from warehouse.stock_item_holdings sih
join warehouse.stock_items si on sih.stock_item_id = si.stock_item_id
where sih.quantity_on_hand <= sih.reorder_level;

-- 8. Top 5 items with the most inventory money tied up in warehouse
select
    si.stock_item_name,
    sih.quantity_on_hand,
    sih.target_stock_level,
    sih.last_cost_price,
    round((sih.quantity_on_hand * sih.last_cost_price)::numeric, 2) as total_holding_valuation
from warehouse.stock_item_holdings sih
join warehouse.stock_items si on sih.stock_item_id = si.stock_item_id
order by total_holding_valuation desc
limit 5;

-- 9. Check packaging sizes: Each box/outer must hold at least 1 unit
select
    count(*) as total_skus,
    sum(case when quantity_per_outer is null or quantity_per_outer <= 0 then 1 else 0 end) as invalid_conversion_count,
    min(quantity_per_outer) as min_qty_per_outer,
    max(quantity_per_outer) as max_qty_per_outer
from warehouse.stock_items;

-- 10. Delivery speed: How many days did suppliers actually take to deliver?
select
    min(pol.last_receipt_date - po.order_date) as min_delivery_days,
    max(pol.last_receipt_date - po.order_date) as max_delivery_days,
    round(avg(pol.last_receipt_date - po.order_date), 1) as avg_delivery_days,
    sum(case when pol.last_receipt_date < po.order_date then 1 else 0 end) as invalid_negative_lead_time_count
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
where pol.is_order_line_finalized = true;

-- 11. Sanity check: Make sure order headers and order lines agree on status
select
    sum(case when po.is_order_finalized = true and pol.is_order_line_finalized = false then 1 else 0 end) as closed_header_open_line_count,
    sum(case when po.is_order_finalized = false and pol.is_order_line_finalized = true then 1 else 0 end) as open_header_closed_line_count
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id;
