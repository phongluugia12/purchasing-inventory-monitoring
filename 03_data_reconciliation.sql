select 
    '1. Purchasing: Tong gia tri dat mua' as kpi_metric,
    round(sum(line_ordered_amount)::numeric, 2) as benchmark_value,
    'USD' as unit
from analytics.vw_fact_purchase_order_lines

union all

select 
    '2. Purchasing: Tong so dong don hang',
    count(*),
    'lines'
from analytics.vw_fact_purchase_order_lines

union all

select 
    '3. Inventory: Tong gia tri von ton kho',
    round(sum(total_inventory_valuation)::numeric, 2),
    'USD'
from analytics.vw_fact_inventory_snapshot

union all

select 
    '4. Inventory: Tong so ma hang (SKU)',
    count(*),
    'items'
from analytics.vw_fact_inventory_snapshot

union all

select 
    '5. Inventory: So SKU duoi muc an toan (Understocked)',
    count(*),
    'items'
from analytics.vw_fact_inventory_snapshot
where inventory_health_status = 'Understocked';

with ranked_inventory as(
	select 
		stock_item_id,
		stock_item_name,
		quantity_on_hand,
		last_cost_price,
		total_inventory_valuation,
		sum(total_inventory_valuation) over(
			order by total_inventory_valuation desc
		) as running_total_valuation,
		
		sum(total_inventory_valuation) over() as grand_total_valuation
	from analytics.vw_fact_inventory_snapshot
)
select 
	stock_item_id,
	stock_item_name,
	quantity_on_hand,
	last_cost_price,
	round((running_total_valuation / grand_total_valuation * 100)::numeric,2) as cumulative_pct,
	case
		when (running_total_valuation / grand_total_valuation * 100) <= 80 then 'Nhom A(Gia tri cao)'
		when (running_total_valuation / grand_total_valuation * 100) <= 95 then 'Nhom B(Gia tri trung binh)'
		else 'Nhom C gia tri thap'
	end as abc_category
from ranked_inventory
;