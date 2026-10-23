-- Kiem tra xem 2 mat hang understocked da co don dat mua dang cho nhan (PO open) chua
with understocked_items as (
    select 
        stock_item_id,
        stock_item_name,
        quantity_on_hand,
        reorder_level,
        target_stock_level
    from analytics.vw_fact_inventory_snapshot
    where inventory_health_status = 'Understocked'
),
open_po_lines as (
    select 
        stock_item_id,
        sum(ordered_quantity - received_quantity) as outstanding_quantity
    from analytics.vw_fact_purchase_order_lines
    where is_order_line_finalized = false
    group by stock_item_id
)
select 
    u.stock_item_id,
    u.stock_item_name,
    u.quantity_on_hand,
    u.reorder_level,
    u.target_stock_level,
    coalesce(o.outstanding_quantity, 0) as incoming_quantity,
    case 
        when o.outstanding_quantity is null or o.outstanding_quantity = 0 then 'Ton thap, CHUA co hang cho'
        when (u.quantity_on_hand + o.outstanding_quantity) < u.reorder_level then 'Ton thap, hang cho VE KHONG DU'
        else 'Ton thap, DA CO hang cho bu du'
    end as action_category
from understocked_items u
left join open_po_lines o on u.stock_item_id = o.stock_item_id;