# Purchasing & Inventory Monitoring

Status: preparation only. No database restored, queries executed, or findings verified yet.

## Scope

- Domain: purchasing and inventory monitoring for a fictional wholesaler.
- Dataset: Microsoft's Wide World Importers operational sample database (not the prebuilt DW).
- Tools: SQL Server and Power BI. dbt is optional after the first complete version.
- Deliverables: reproducible SQL, validation checks, two report pages, screenshots, and a concise README.
- Planning target: 7-10 focused working days at approximately 3-4 hours per day; not a guaranteed deadline.

## Business questions

1. Which purchase orders or lines remain open?
2. Which open orders have passed their expected delivery date at a defensible reporting date?
3. Which stock items are below their reorder level?
4. Which low-stock items already have outstanding purchase quantities?

These questions are provisional until the actual sample has been profiled. Do not fabricate exceptions if the sample has none.

## Source tables

- Purchasing.PurchaseOrders: one purchase order per row.
- Purchasing.PurchaseOrderLines: one purchase order line per row.
- Purchasing.Suppliers: supplier reference data.
- Warehouse.StockItems: stock item reference data, including packaging information.
- Warehouse.StockItemHoldings: current stock state, not a historical stock snapshot series.

## Workflow and review gates

### 1. Environment and source

- [ ] Install a local SQL Server Developer instance for learning/non-production use.
- [ ] Record server version, edition, instance name and connection method; never record passwords.
- [ ] Obtain the operational Wide World Importers sample from Microsoft.
- [ ] Inspect backup metadata before restoring to a new database; do not overwrite an existing database.
- [ ] Confirm all five source tables exist.

### 2. Learn and profile

- [ ] Explain order versus order line, partial receipt, finalized status, on-hand stock and reorder level.
- [ ] Record row counts, keys, date coverage and status distributions.
- [ ] Check whether open orders, overdue candidates and low-stock items are present.
- [ ] Verify units and conversions before comparing purchased and stocked quantities.
- [ ] Establish a reporting-date assumption consistent with the sample state; do not blindly use today's date.
- [ ] Approve final KPI definitions and narrow scope if sample coverage is insufficient.

### 3. SQL reporting layer

- [ ] Preserve source tables; create derived objects in a separate reporting schema.
- [ ] Separate purchase-line data from item-level inventory data.
- [ ] Aggregate outstanding purchases to item level before joining inventory.
- [ ] Define outstanding quantity only for eligible open lines; review over-receipts separately.
- [ ] Count distinct orders when reporting order-level metrics.

### 4. Power BI

- [ ] Page 1: Purchasing Monitor, including an actionable detail table.
- [ ] Page 2: Inventory Watchlist, including stock and outstanding purchase quantities.
- [ ] Show the reporting-date assumption and simulated-data disclaimer.
- [ ] Verify KPI totals and filtered results against SQL.

### 5. Validation and delivery

- [ ] Test primary-key uniqueness, missing keys, orphan references and join fan-out.
- [ ] Review missing dates, inconsistent statuses and quantity anomalies.
- [ ] Trace a few actual orders and items from source to report.
- [ ] Write evidence-backed observations, follow-up actions and limitations.
- [ ] Document how to reproduce the project without credentials or machine-specific secrets.
- [ ] Review files and Git repository boundaries before any staging or publishing.
- [ ] Practise a five-minute explanation before adding the project to the CV as completed.

## Interpretation boundaries

- LastReceiptDate is the last recorded receipt date, not automatically the first receipt or completion date.
- Finalized lines can have received quantities different from ordered quantities.
- Current status does not reconstruct historical backlog at arbitrary earlier dates.
- Current holdings alone do not establish historical stockout days, lost sales or inventory turnover.
- Low stock is a prompt to review, not an automatic purchase recommendation.
- No causal supplier blame or claimed real-world savings from simulated data.

## Environment check: 2026-09-29

- No local SQL Server instance was found in the checked Windows services or SQL instance registry location.
- sqlcmd was not found on PATH. This does not rule out all portable or remote installations.
- The parent directory C:/Users/phong/Desktop/project already has a Git repository and pre-existing changes.
- No Git initialization, staging, commits, installations or database changes have been performed for this project.

## Official sources

- SQL Server Developer downloads: https://www.microsoft.com/en-us/sql-server/sql-server-downloads
- Business context: https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-what-is
- Sample release: https://github.com/microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0

