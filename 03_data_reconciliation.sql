-- 03_data_reconciliation.sql
-- Project: Purchasing & Inventory Monitoring
-- Purpose: Reconcile key purchasing and inventory KPIs across raw tables, views, and Power BI benchmark figures, and run integrity checks (verifying 9 conformed metrics and 4 zero-violation integrity assertions).

-- ====================================================================================================
-- SECTION 1: PURCHASING NUMBERS CHECK
-- Compares raw tables vs analytics views vs Power BI figures.
-- Note: 'power_bi_benchmark' is a static reference target verified against Power BI report card visuals.
-- Each metric runs in its own subquery so rows never multiply each other.
-- ====================================================================================================

select
    '1. Total Historical PO Value' as metric_name,
    (select round(sum(ordered_outers * expected_unit_price_per_outer)::numeric, 2) from purchasing.purchase_order_lines) as source_raw,
    (select round(sum(line_ordered_amount)::numeric, 2) from analytics.vw_fact_purchase_order_lines) as view_analytics,
    946715166.50 as power_bi_benchmark,
    'USD' as unit

union all

select
    '2. Total Historical PO Lines',
    (select count(*) from purchasing.purchase_order_lines),
    (select count(*) from analytics.vw_fact_purchase_order_lines),
    8367,
    'lines'

union all

select
    '3. Active Open Purchase Orders',
    (select count(distinct po.purchase_order_id)
     from purchasing.purchase_orders po
     join purchasing.purchase_order_lines pol on po.purchase_order_id = pol.purchase_order_id
     where po.is_order_finalized = false and pol.is_order_line_finalized = false),
    (select count(distinct purchase_order_id) from analytics.vw_fact_purchase_order_lines where is_order_finalized = false and is_order_line_finalized = false),
    2,
    'orders'

union all

select
    '4. Active Open PO Lines',
    (select count(*)
     from purchasing.purchase_order_lines pol
     join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
     where po.is_order_finalized = false and pol.is_order_line_finalized = false),
    (select count(*)
     from analytics.vw_fact_purchase_order_lines
     where is_order_finalized = false and is_order_line_finalized = false),
    9,
    'lines'

union all

select
    '5. Total Pending Outers (Open Lines)',
    (select sum(case when pol.ordered_outers > coalesce(pol.received_outers, 0) then pol.ordered_outers - coalesce(pol.received_outers, 0) else 0 end)
     from purchasing.purchase_order_lines pol
     join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
     where po.is_order_finalized = false and pol.is_order_line_finalized = false),
    (select sum(case when ordered_outers > coalesce(received_outers, 0) then ordered_outers - coalesce(received_outers, 0) else 0 end)
     from analytics.vw_fact_purchase_order_lines
     where is_order_finalized = false and is_order_line_finalized = false),
    25949,
    'outers'

union all

select
    '6. Overdue Open Lines (as of 2016-05-31)',
    (select count(*)
     from purchasing.purchase_order_lines pol
     join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
     where po.is_order_finalized = false and pol.is_order_line_finalized = false and po.expected_delivery_date < date '2016-05-31'),
    (select count(*)
     from analytics.vw_fact_purchase_order_lines
     where is_order_finalized = false and is_order_line_finalized = false and delivery_status = 'Missed date'),
    0,
    'lines';


-- ====================================================================================================
-- SECTION 2: INVENTORY NUMBERS CHECK
-- Compares warehouse stock holdings vs inventory snapshot view vs Power BI figures.
-- ====================================================================================================

select
    '1. Total Current Inventory Valuation' as metric_name,
    (select round(sum(quantity_on_hand * last_cost_price)::numeric, 2) from warehouse.stock_item_holdings) as source_raw,
    (select round(sum(total_inventory_valuation)::numeric, 2) from analytics.vw_fact_inventory_snapshot) as view_analytics,
    475279296.35 as power_bi_benchmark,
    'USD' as unit

union all

select
    '2. Total Active Stock Items (SKUs)',
    (select count(*) from warehouse.stock_item_holdings),
    (select count(*) from analytics.vw_fact_inventory_snapshot),
    227,
    'items'

union all

select
    '3. Understocked SKUs (<= Reorder Level)',
    (select count(*) from warehouse.stock_item_holdings where quantity_on_hand > 0 and quantity_on_hand <= reorder_level),
    (select count(*) from analytics.vw_fact_inventory_snapshot where inventory_health_status = 'Understocked'),
    2,
    'items';


-- ====================================================================================================
-- SECTION 3: DATA INTEGRITY TESTS (4 CHECKS)
-- Automated checks to catch broken links or data conflicts. All 4 tests must show PASS (0 errors).
-- ====================================================================================================

-- Test 1: Check if any order header is closed but its line is still open
select
    '1. Header Closed but Line Open Mismatch' as check_name,
    count(*) as violation_count,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as audit_status
from purchasing.purchase_order_lines pol
join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
where po.is_order_finalized = true and pol.is_order_line_finalized = false

union all

-- Test 2: Check if any raw purchase order line refers to a missing stock item (orphan foreign key)
select
    '2. Orphan Stock Items in Raw PO Lines',
    count(*),
    case when count(*) = 0 then 'PASS' else 'FAIL' end
from purchasing.purchase_order_lines pol
left join warehouse.stock_items si on pol.stock_item_id = si.stock_item_id
where si.stock_item_id is null

union all

-- Test 3: Check if any order date is missing from our calendar (Dim_Date)
select
    '3. Order Dates Missing from Dim_Date',
    count(*),
    case when count(*) = 0 then 'PASS' else 'FAIL' end
from analytics.vw_fact_purchase_order_lines f
left join analytics.vw_dim_date d on f.order_date = d.date_key
where d.date_key is null

union all

-- Test 4: Check if any open order line has received more items than ordered
select
    '4. Over-receipt on Open Lines (Received > Ordered)',
    count(*),
    case when count(*) = 0 then 'PASS' else 'FAIL' end
from purchasing.purchase_order_lines
where is_order_line_finalized = false and received_outers > ordered_outers;


-- ====================================================================================================
-- SECTION 4: ABC INVENTORY ANALYSIS (PARETO 80/20)
-- Ranks all 227 products by inventory value from highest to lowest.
-- Group A = Top 80% of money | Group B = Next 15% (80-95%) | Group C = Bottom 5% (95-100%)
-- ====================================================================================================

with ranked_inventory as (
    select
        stock_item_id,
        stock_item_name,
        quantity_on_hand,
        last_cost_price,
        total_inventory_valuation,
        -- Running total sorted from highest valuation to lowest
        sum(total_inventory_valuation) over (order by total_inventory_valuation desc, stock_item_id asc) as running_total,
        sum(total_inventory_valuation) over () as grand_total
    from analytics.vw_fact_inventory_snapshot
)
select
    stock_item_id,
    stock_item_name,
    quantity_on_hand,
    last_cost_price,
    total_inventory_valuation,
    round((running_total / nullif(grand_total, 0) * 100)::numeric, 2) as cumulative_pct,
    case
        when (running_total / nullif(grand_total, 0) * 100) <= 80.00 then 'Class A (High Capital Tied Up)'
        when (running_total / nullif(grand_total, 0) * 100) <= 95.00 then 'Class B (Medium Capital Tied Up)'
        else 'Class C (Low Capital Tied Up)'
    end as abc_category
from ranked_inventory;
