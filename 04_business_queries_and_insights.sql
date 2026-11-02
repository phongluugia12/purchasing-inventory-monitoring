-- 04_business_queries_and_insights.sql
-- Project: Purchasing & Inventory Monitoring
-- Purpose: Answer key business questions: Which items are running out of stock? Which items have too much stock?

-- ====================================================================================================
-- QUERY 1: Classify all 227 products into 7 action categories (What should the purchasing team do?)
-- Categories:
--   1. Out of stock: completely empty (quantity <= 0)
--   2. Low stock - No open PO: running low, and nobody has placed an order yet
--   3. Low stock - Incoming PO insufficient: running low, an order was placed but still not enough
--   4. Low stock - Covered by open PO: running low, but an incoming order is enough to refill
--   5. Overstocked - Review incoming PO: already holding too much, but someone still ordered more! (Check to cancel/delay)
--   6. Overstocked - Excess holding: holding too much stock, money tied up
--   7. Within target: healthy stock level
-- ====================================================================================================

with open_po_summary as (
    -- Count open orders and incoming quantities for each product.
    -- Guard each line so over-received items do not produce negative numbers.
    select
        pol.stock_item_id,
        count(distinct pol.purchase_order_id) as open_po_count,
        count(*) as open_line_count,
        sum(
            case
                when pol.ordered_quantity > coalesce(pol.received_quantity, 0)
                then pol.ordered_quantity - coalesce(pol.received_quantity, 0)
                else 0
            end
        ) as outstanding_quantity,
        min(po.expected_delivery_date) as earliest_expected_delivery
    from analytics.vw_fact_purchase_order_lines pol
    join purchasing.purchase_orders po on pol.purchase_order_id = po.purchase_order_id
    where po.is_order_finalized = false
      and pol.is_order_line_finalized = false
    group by pol.stock_item_id
),
inventory_action_matrix as (
    select
        inv.stock_item_id,
        inv.stock_item_name,
        inv.supplier_id,
        inv.quantity_on_hand,
        inv.reorder_level,
        inv.target_stock_level,
        inv.total_inventory_valuation,
        coalesce(po.outstanding_quantity, 0) as incoming_quantity,
        po.earliest_expected_delivery,
        case
            when inv.quantity_on_hand <= 0 then 'Out of stock'
            when inv.quantity_on_hand <= inv.reorder_level and coalesce(po.outstanding_quantity, 0) = 0
                then 'Low stock - No open PO'
            when inv.quantity_on_hand <= inv.reorder_level and (inv.quantity_on_hand + coalesce(po.outstanding_quantity, 0)) < inv.reorder_level
                then 'Low stock - Incoming PO insufficient'
            when inv.quantity_on_hand <= inv.reorder_level
                then 'Low stock - Covered by open PO'
            when inv.quantity_on_hand > inv.target_stock_level and coalesce(po.outstanding_quantity, 0) > 0
                then 'Overstocked - Review incoming PO'
            when inv.quantity_on_hand > inv.target_stock_level
                then 'Overstocked - Excess holding'
            else 'Within target'
        end as action_category
    from analytics.vw_fact_inventory_snapshot inv
    left join open_po_summary po on inv.stock_item_id = po.stock_item_id
)
select
    stock_item_id,
    stock_item_name,
    quantity_on_hand,
    reorder_level,
    target_stock_level,
    incoming_quantity,
    earliest_expected_delivery,
    total_inventory_valuation,
    action_category
from inventory_action_matrix
order by
    case action_category
        when 'Out of stock' then 1
        when 'Low stock - No open PO' then 2
        when 'Low stock - Incoming PO insufficient' then 3
        when 'Low stock - Covered by open PO' then 4
        when 'Overstocked - Review incoming PO' then 5
        when 'Overstocked - Excess holding' then 6
        else 7
    end,
    total_inventory_valuation desc;


-- ====================================================================================================
-- QUERY 2: Deep dive on the 2 low-stock products (White 5XL T-shirt & Brown Shipping Carton)
-- Both items are below their reorder level. When will their incoming orders actually arrive?
-- ====================================================================================================

with low_stock_exceptions as (
    select
        inv.stock_item_id,
        inv.stock_item_name,
        inv.quantity_on_hand,
        inv.reorder_level,
        inv.target_stock_level,
        coalesce(
            sum(
                case
                    when pol.ordered_quantity > coalesce(pol.received_quantity, 0)
                    then pol.ordered_quantity - coalesce(pol.received_quantity, 0)
                    else 0
                end
            ), 0
        ) as incoming_quantity,
        min(po.expected_delivery_date) as earliest_arrival_date
    from analytics.vw_fact_inventory_snapshot inv
    left join analytics.vw_fact_purchase_order_lines pol
        on inv.stock_item_id = pol.stock_item_id
       and pol.is_order_finalized = false
       and pol.is_order_line_finalized = false
    left join purchasing.purchase_orders po
        on pol.purchase_order_id = po.purchase_order_id
    where inv.inventory_health_status = 'Understocked'
    group by
        inv.stock_item_id,
        inv.stock_item_name,
        inv.quantity_on_hand,
        inv.reorder_level,
        inv.target_stock_level
)
select
    stock_item_id,
    stock_item_name,
    quantity_on_hand,
    reorder_level,
    incoming_quantity,
    earliest_arrival_date,
    -- Days until the order arrives (Anchor report date is 2016-05-31)
    (earliest_arrival_date - date '2016-05-31') as days_until_arrival,
    case
        when incoming_quantity = 0 then 'Critical: Below reorder level with no open PO; immediate replenishment required'
        when (quantity_on_hand + incoming_quantity) < reorder_level then 'High: Pending order volume insufficient to reach reorder threshold'
        when earliest_arrival_date is null then 'Nominally covered to reorder level; arrival date missing, poses stockout hazard'
        when earliest_arrival_date < date '2016-05-31' then 'Nominally covered to reorder level; order is overdue (' || (date '2016-05-31' - earliest_arrival_date)::text || ' days late), high stockout risk'
        else 'Nominally covered to reorder level; arrival in ' || (earliest_arrival_date - date '2016-05-31')::text || ' days poses stockout hazard if daily consumption exhausts buffer'
    end as operational_recommendation
from low_stock_exceptions;
