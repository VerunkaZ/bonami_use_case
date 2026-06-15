# Datový Model a Dokumentace Projektu
## E-Commerce Analytics Pipeline — Keboola

## 1. Architektura — přehled

Pipeline je navržena jako čtyřvrstvý model. Každá vrstva má jednu zodpovědnost a konzistentní bucket v Keboola Storage.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  VRSTVA 0 — SOURCE (Raw)           in.c-source                           │
│  Originální data ze zdrojového systému, bez jakýchkoliv úprav            │
│  orders │ products │ users                                                │
└─────────────────────────────┬────────────────────────────────────────────┘
                              │
          ┌───────────────────┼──────────────────────┐
          ▼                   ▼                      ▼
┌─────────────────┐  ┌─────────────────┐   ┌───────────────────────────┐
│ VRSTVA 1        │  │ VRSTVA 2        │   │  (paralelně s vrstvou 1)  │
│ STAGING         │  │ AUDIT           │   │                           │
│ out.c-staging   │  │ out.c-audit     │   │                           │
│                 │  │                 │   │                           │
│ stg_orders      │  │ data_quality_   │   │                           │
│ stg_products    │  │ issues          │   │                           │
│ stg_users       │  │                 │   │                           │
└────────┬────────┘  └─────────────────┘   └───────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  VRSTVA 3 — ANALYTICS MART         out.c-analytics                       │
│  Business-ready agregace; jediná vrstva vystavená do BI nástroje         │
│                                                                          │
│  monthly_revenue_by_country │ category_performance                       │
│  user_segments              │ cohort_retention                            │
└──────────────────────────────┬───────────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   BI TOOL            │
                    │   (Metabase, Tableau) │
                    └──────────────────────┘
```

---

## 2. Vrstva 0 — Source (Raw)

**Bucket:** `in.c-source`
**Zodpovědnost:** Uložení dat přesně tak, jak přišla ze zdrojového systému. Nulová transformace.

| Tabulka | Klíčové sloupce | Popis |
|---------|-----------------|-------|
| `orders` | order_id, user_id, product_id, order_date, quantity, status, revenue_czk, discount_pct | Transakční záznamy e-commerce objednávek |
| `products` | product_id, product_name, category, price_czk, margin_pct, is_active | Produktový katalog |
| `users` | user_id, country, acquisition_channel, registered_at, age_group | Zákaznická databáze |

**Pravidla:**
- Žádné transformace, žádné přejmenování sloupců
- Full load při každém spuštění (zdrojový systém nedodává delty)
- Data mohou obsahovat nevalidní hodnoty — to je účel auditu a stagingu
- Staging ani analytické tabulky nečtou přímo z `in.c-source` — výjimkou je auditní vrstva (viz níže)

---

## 3. Vrstva 1 — Staging (Cleaned)

**Bucket:** `out.c-staging`
**Zodpovědnost:** Jedna čistá, přetypovaná, deduplikovaná kopie každé zdrojové entity s přiloženými quality flagy.

**Záruky vrstvy:**
- 1 řádek per primární klíč (deduplikace proběhla)
- Validní datové typy (DATE, NUMBER — ne VARCHAR pro číselné hodnoty)
- Normalizované statusy a kategorie
- Quality flagy (`is_*`) pro downstream filtrování bez opakování business logiky

| Tabulka | Zdrojová tabulka | Hlavní transformace |
|---------|------------------|---------------------|
| `stg_orders` | `in.c-source.orders` | Normalizace statusu (kompletní→completed, LOWER/TRIM), deduplication (preference: completed > nejnovější datum), quality flagy |
| `stg_products` | `in.c-source.products` | INITCAP kategorie, normalizace is_active (string→bool), deduplication (preference: is_active=1 > vyšší cena) |
| `stg_users` | `in.c-source.users` | Validace country/channel/age_group proti číselníkům, deduplication (nejnovější registered_at) |

**Quality flagy (konvence `is_*`):**

| Flag | Tabulka | Meaning |
|------|---------|---------|
| `is_revenue_suspicious` | stg_orders | completed objednávka s revenue=0 nebo NULL |
| `is_status_unknown` | stg_orders | status mimo platný číselník (po normalizaci) |
| `is_quantity_invalid` | stg_orders | quantity ≤ 0 nebo neparsovatelné |
| `is_price_invalid` | stg_products | price_czk ≤ 0 nebo NULL |
| `is_margin_out_of_range` | stg_products | margin_pct mimo rozsah 0–1 |
| `is_category_missing` | stg_products | chybí nebo prázdná category |
| `is_age_group_unknown` | stg_users | age_group NULL nebo mimo číselník |
| `is_country_unknown` | stg_users | country mimo povolené hodnoty |
| `is_channel_unknown` | stg_users | acquisition_channel mimo povolené hodnoty |
| `is_registered_at_invalid` | stg_users | registered_at neparsovatelné jako DATE |

**Audit metadata:** každá staging tabulka obsahuje `loaded_at` (TIMESTAMP) a `source_table` (VARCHAR) pro lineage tracking.

---

## 4. Vrstva 2 — Audit (Data Quality)

**Bucket:** `out.c-audit`
**Zodpovědnost:** Kvantifikace datových problémů ve zdrojových datech. Čte přímo z `in.c-source` (ne ze stagingu), aby zachytila problémy ještě před čištěním.

| Tabulka | Popis |
|---------|-------|
| `data_quality_issues` | Jeden řádek per (table_name, issue_type) s počtem zasažených řádků, business popisem a doporučeným fixem |

**Schéma:**
```
table_name        VARCHAR    -- "orders" / "products" / "users"
issue_type        VARCHAR    -- strojově čitelný klíč (např. "null_in_key_order_id")
affected_rows     NUMBER     -- počet řádků s daným problémem
description       VARCHAR    -- lidsky čitelný popis problému (z issue_catalog)
recommended_fix   VARCHAR    -- doporučená oprava (z issue_catalog)
```

**Použití:** Tato tabulka je určena pro datový tým a data stewardy — ne pro BI uživatele. Lze ji napojit na monitoring nebo alerting (e-mail/Slack notifikace při `affected_rows > threshold`).

---

## 5. Vrstva 3 — Analytics Mart

**Bucket:** `out.c-analytics`
**Zodpovědnost:** Business-ready agregace připravené pro přímé napojení do BI nástroje. Čte ze `out.c-staging` — nikdy ze zdrojové vrstvy.

### `monthly_revenue_by_country`

**Účel:** Trend měsíčních tržeb per country s MoM growth pro revenue dashboard.
**Filtr:** Pouze `completed` objednávky s `is_revenue_suspicious = 0`.

| Sloupec | Typ | Popis |
|---------|-----|-------|
| `month` | DATE | Prvního dne daného měsíce (DATE_TRUNC) |
| `country` | VARCHAR | ISO kód země nebo 'UNKNOWN' |
| `revenue_czk` | NUMBER(18,2) | Celková tržba za měsíc a zemi |
| `prev_month_revenue_czk` | NUMBER(18,2) | Tržba předchozího měsíce (LAG) |
| `mom_growth_pct` | NUMBER(10,2) | MoM growth v % (NULL pro první měsíc) |

---

### `category_performance`

**Účel:** Výkonnostní přehled produktových kategorií pro product management.
**Filtr:** Pouze `completed` objednávky, kategorie NOT NULL.

| Sloupec | Typ | Popis |
|---------|-----|-------|
| `category` | VARCHAR | Normalizovaný název kategorie (INITCAP) |
| `total_revenue_czk` | NUMBER(18,2) | Celková tržba kategorie |
| `avg_margin_pct` | NUMBER(5,4) | Průměrná marže váhovaná počtem objednávek |
| `order_count` | NUMBER | Počet objednávek |
| `avg_discount_pct` | NUMBER(5,4) | Průměrná sleva |
| `revenue_rank` | NUMBER | Rank dle tržeb (1 = nejvyšší) |

---

### `user_segments`

**Účel:** Zákaznická segmentace pro CRM, retention analýzy a personalizaci.
**Logika:** Každý uživatel dostane jeden segment. Priorita segmentů (vyšší číslo = nižší priorita):

| Segment | Podmínka |
|---------|----------|
| `new_user` | Registrace < 180 dní od referenčního data |
| `lost` | Nikdy nenakoupil NEBO poslední nákup > 365 dní |
| `at_risk` | Poslední nákup 180–365 dní |
| `high_value` | Celkové tržby > 20 000 CZK |
| `regular` | Ostatní aktivní zákazníci |

> **Business poznámka:** Segment `new_user` má aktuálně prioritu nad `high_value`. Zákazník s vysokými tržbami a registrací < 180 dní = `new_user`. Je-li záměrem odlišit, doporučujeme pořadí upravit a zdokumentovat.

| Sloupec | Typ | Popis |
|---------|-----|-------|
| `user_id` | VARCHAR | Identifikátor zákazníka |
| `country` | VARCHAR | Země (z stg_users) |
| `age_group` | VARCHAR | Věková skupina |
| `registered_at` | DATE | Datum registrace |
| `last_order_date` | DATE | Datum poslední completed objednávky |
| `order_count` | NUMBER | Počet completed objednávek |
| `total_revenue_czk` | NUMBER(18,2) | Celkové tržby |
| `days_since_registered` | NUMBER | Počet dní od registrace |
| `days_since_last_order` | NUMBER | Počet dní od poslední objednávky |
| `segment` | VARCHAR | Přiřazený segment |

---

### `cohort_retention`

**Účel:** Kohortová analýza retence — % zákazníků z každé registrační kohorty, kteří nakoupili v měsíci 0–3 po registraci.

| Sloupec | Typ | Popis |
|---------|-----|-------|
| `cohort_month` | VARCHAR | Měsíc registrace kohorty (formát YYYY-MM) |
| `cohort_size` | NUMBER | Počet unikátních uživatelů v kohortě |
| `month_0_users` | NUMBER | Uživatelé, kteří nakoupili v měsíci registrace |
| `month_0_retention_pct` | NUMBER(5,2) | Retence v měsíci 0 (%) |
| `month_1_users` | NUMBER | Uživatelé, kteří nakoupili měsíc po registraci |
| `month_1_retention_pct` | NUMBER(5,2) | Retence v měsíci 1 (%) |
| `month_2_users` | NUMBER | ... |
| `month_2_retention_pct` | NUMBER(5,2) | ... |
| `month_3_users` | NUMBER | ... |
| `month_3_retention_pct` | NUMBER(5,2) | ... |

---

## 6. Konvence pojmenování

### 6.1 Buckety

| Pattern | Příklad | Vrstva |
|---------|---------|--------|
| `in.c-{source}` | `in.c-source` | Source / Raw |
| `out.c-staging` | `out.c-staging` | Staging |
| `out.c-audit` | `out.c-audit` | Audit / DQ |
| `out.c-analytics` | `out.c-analytics` | Analytics Mart |

Při napojení dalšího zdroje (např. CRM): `in.c-crm`, staging: `out.c-staging` (sdílený bucket), analytics: `out.c-analytics` (sdílený bucket).

### 6.2 Tabulky

| Vrstva | Pattern | Příklady |
|--------|---------|----------|
| Source | `{entity}` | `orders`, `products`, `users` |
| Staging | `stg_{source_entity}` | `stg_orders`, `stg_products` |
| Audit | `{domain}_{report_type}` | `data_quality_issues` |
| Analytics | `{grain}_{metric}_{dimension}` | `monthly_revenue_by_country`, `category_performance` |

### 6.3 Sloupce

| Pattern | Příklady |
|---------|---------|
| `snake_case` vždy | `order_id`, `revenue_czk` |
| ID sloupce: `{entity}_id` | `order_id`, `user_id`, `product_id` |
| Quality flagy: `is_{condition}` | `is_revenue_suspicious`, `is_active` |
| Timestampy: `{akce}_at` | `registered_at`, `loaded_at` |
| Numerické metriky: `{metrika}_{jednotka}` | `revenue_czk`, `margin_pct`, `discount_pct` |
| Ranky: `{metrika}_rank` | `revenue_rank` |
| Segmenty/kategorie: `{entity}` | `segment`, `category`, `age_group` |

---

## 7. BI Expozice

### 7.1 Tabulky vystavené do BI

Pouze tabulky z `out.c-analytics`. Staging a audit jsou technické vrstvy, ne pro business uživatele.

| Tabulka | BI Dashboard | Klíčové metriky | Frekvence aktualizace |
|---------|-------------|-----------------|----------------------|
| `monthly_revenue_by_country` | Revenue Trend | Celková tržba, MoM growth % | Denně (6:00 UTC) |
| `category_performance` | Product Analytics | Tržby, marže, rank kategorií | Denně |
| `user_segments` | Customer Health | Segment distribuce, RFM metriky | Denně |
| `cohort_retention` | Retention Dashboard | Retence % per kohorta a měsíc | Denně |

### 7.2 Co se do BI nevystavuje a proč

| Bucket / Tabulka | Důvod nevystavení |
|------------------|-------------------|
| `in.c-source.*` | Raw data bez záruk kvality; duplicity, neplatné typy, nekonzistentní statusy |
| `out.c-staging.*` | Technická vrstva; quality flagy (`is_*`) jsou interní nástroj, ne business metrika |
| `out.c-audit.data_quality_issues` | Provozní DQ report pro datový tým; business uživatelé by neinterpretovali správně |

### 7.3 Doporučená joins v BI (pro ad-hoc analýzy)

Analytické tabulky jsou navrženy jako self-contained — BI dashboardy by neměly joinovat přes vrstvy. Výjimka: ad-hoc analýzy mohou joinovat `user_segments` s `monthly_revenue_by_country` přes `country` pro segmentovaný revenue pohled.

---

## 8. Datové závislosti & pořadí orchestrace

```
[1] Source Load (extrakce ze zdrojového systému)
         │
         ├──[2A] stg_orders    ──┐
         ├──[2B] stg_products    ├── PARALELNĚ (žádné vzájemné závislosti)
         ├──[2C] stg_users     ──┘
         │
         └──[2D] data_quality_issues  ── PARALELNĚ s [2A-2C] (čte ze Source, ne ze Staging)
                      │
         ┌────────────┴────────────────────────┐
         │                                     │
    [3A] monthly_revenue_by_country       [3B] category_performance
    [3C] user_segments                         │
    (všechny PARALELNĚ po dokončení [2A-2C])  │
         │
         │
    [4]  cohort_retention  ── závisí na [2A] stg_orders + [3C] user_segments
```

**Poznámka k paralelizaci:**
- Kroky 2A, 2B, 2C lze spustit paralelně — každý čte z jiné zdrojové tabulky
- Krok 2D (audit) lze spustit paralelně s kroky 2A–2C — čte ze Source, ne ze Staging
- Kroky 3A, 3B, 3C lze spustit paralelně po dokončení 2A–2C
- Krok 4 musí čekat na 2A (stg_orders) i 3C (user_segments)

---

## 9. Glosář

| Termín | Definice v kontextu projektu |
|--------|------------------------------|
| **completed order** | Objednávka se statusem `completed` (po normalizaci; zahrnuje původní `kompletní`, `COMPLETED`, `Completed`) |
| **is_revenue_suspicious** | Flag = 1, pokud má completed objednávka revenue = 0 nebo NULL |
| **cohort** | Skupina uživatelů registrovaných ve stejném kalendářním měsíci |
| **cohort retention** | % uživatelů z kohorty, kteří dokončili alespoň 1 completed objednávku v daném měsíčním offsetu |
| **MoM growth** | Month-over-Month growth: `(aktuální - předchozí) / předchozí × 100` |
| **referenční datum** | `MAX(order_date)` ze stg_orders; použito namísto `CURRENT_DATE` pro historická data |
| **segment priority** | Pořadí podmínek v CASE WHEN; segment přiřazen dle první splněné podmínky |
| **full load** | Tabulka se při každém spuštění přepíše kompletně (`CREATE OR REPLACE`); žádná inkrementa |
| **quality flag** | Boolean sloupec (`is_*`) v staging tabulkách označující potenciálně problematický řádek |
| **anti-join** | JOIN pattern pro detekci chybějících FK: `LEFT JOIN ... WHERE right.id IS NULL` |
