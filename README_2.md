# ClearPort Analytics on Snowflake

Where does demurrage money go at Nigerian ports? I loaded 3,025 raw shipment records into Snowflake, cleaned them with SQL, and analysed clearance times and demurrage costs across 5 ports.

I spent 7 years clearing cargo at Apapa. This is the analysis I wish we had.

## Key findings

- **6 in 10 shipments** went past their free days, costing **$4.19M** in demurrage
- **Apapa** handles 38% of shipments but causes **49% of demurrage** ($2.05M) and is the slowest port (9.6 days)
- **Missing documents** is the single biggest cost: **$1.6M (38%)**. These shipments take **12.9 days** to clear vs **4.9 days** with no delay
- **46% of all demurrage** comes from paperwork problems the importer controls (missing documents and payment delays)
- Shipments with incomplete documents cost **2.3x more** in demurrage on average
- Clearing agents differ by only **1 day**. The problem is the process, not the people

## Data cleaning

| Issue found | Fix |
|---|---|
| 25 duplicate shipment records | Removed with `QUALIFY ROW_NUMBER()` |
| 10 spellings of 5 ports (`APAPA`, `apapa`, `Apapa Port`, `TinCan`...) | Standardised with `CASE` |
| 60 arrival dates in `DD/MM/YYYY` format, which broke the monthly trend | Parsed both formats with `COALESCE(TRY_TO_DATE(...))` |
| Blank clearing agents, "None" delay causes | Converted to `Unassigned` / `NULL` |

Result: 3,025 messy rows became 3,000 clean shipments across 5 ports.

## How it's built

1. `RAW_SHIPMENTS` table (all text, so nothing fails on load)
2. Data loaded with `INSERT OVERWRITE`
3. `SHIPMENTS_CLEAN` view that dedupes, standardises and types every column
4. 7 analysis queries (aggregations, window functions, `DATE_TRUNC` trends)
5. Charts built in Snowsight

## Files

- `clearport_snowflake.sql`: setup, cleaning view and all analysis queries
- `1_Snowflake_KPIs.png`: headline numbers
- `2_Snowflake_Delay_Causes.png`: demurrage by delay cause
- `3_Snowflake_Document_Status.png`: demurrage by document status
- `4_Snowflake_SQL.png`: how it was built

![KPIs](1_Snowflake_KPIs.png)
![Delay causes](2_Snowflake_Delay_Causes.png)
![Document status](3_Snowflake_Document_Status.png)

**Tools:** Snowflake, SQL (window functions, QUALIFY, TRY_TO_DATE), Snowsight charts

---
Built by Oluwasegun Adedeji, Data & Automation Analyst, Lagos. [LinkedIn](https://www.linkedin.com/in/oluwasegunadedeji)
