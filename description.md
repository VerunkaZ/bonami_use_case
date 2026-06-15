
Tento projekt má limit 120 minut (spotřebované na běh transformací a query), je třeba rozmyšlet i toto omezení náklady (pozor, Python workspace konzumuje minuty za každou minutu běhu). 

## Kontext

Pracuješ s daty e-commerce platformy. Data jsou uložená v Storage - tabulky `in.c-source.orders`, `in.c-source.products` a `in.c-source.users`. Data nejsou dokonalá - záměrně.

## Schéma tabulek

| Tabulka (Storage) | Klíčové sloupce |
|---|---|
| `in.c-source.orders` | order_id, user_id, product_id, order_date, quantity, status, revenue_czk, discount_pct |
| `in.c-source.products` | product_id, product_name, category, price_czk, margin_pct, is_active |
| `in.c-source.users` | user_id, country, acquisition_channel, registered_at, age_group |

---

## Úkoly

### Úkol 1: Data Quality Audit 

Vytvoř SQL transformaci v Keboola (bucket `out.c-audit`), která identifikuje datové problémy ve všech třech zdrojových tabulkách. Transformace musí mít minimálně 2 bloky. Výstup ulož jako tabulku `out.c-audit.data_quality_issues` se sloupci:

```
table_name, issue_type, affected_rows, description, recommended_fix
```

> **Tip:** Hledej NULL hodnoty, duplicity, nekonzistentní status hodnoty, logické chyby (revenue = 0 u completed objednávky apod.)

**Odevzdat:** Keboola transformace + výstupní tabulka v Storage

---

### Úkol 2: SQL Transformace - Analytická vrstva

Navrhni a implementuj transformační pipeline (bucket `out.c-analytics`) s těmito výstupními tabulkami:

**a) `monthly_revenue_by_country`**
Měsíční tržby per country s MoM growth % (window funkce). Pouze completed objednávky, status normalizovaný.

**b) `category_performance`**
Kategorie, celkové tržby, průměrná marže, počet objednávek, průměrný discount, rank kategorií dle tržeb.

**c) `user_segments`**
Segmentace uživatelů (RFM nebo vlastní logika) s přiřazeným segmentem (např. `high_value`, `at_risk`, `new_user`).

> **Tip:** Dodržuj pojmenování bloků - každá výstupní tabulka = samostatný blok nebo logicky oddělená CTE sekvence.

**Odevzdat:** Keboola SQL transformace, 3 výstupní tabulky v Storage

---

### Úkol 3: Python Transformace `[pokročilé]`

Vytvoř Python transformaci, která:

1. Načte `out.c-analytics.user_segments` a `in.c-source.orders` z Storage (`/data/in/tables/`)
2. Spočítá cohortovou retenci - pro každý měsíc registrace zjisti, kolik % uživatelů nakoupilo v měsíci 0, 1, 2, 3 po registraci
3. Výsledek uloží jako `out.c-analytics.cohort_retention`

Kód musí být čistý, okomentovaný, s error handlingem.

> **Tip:** Vstup/výstup přes `/data/in/tables/` a `/data/out/tables/` - standardní Keboola Python transformace pattern.

**Odevzdat:** Python transformace v Keboola + výstupní tabulka

---

### Úkol 4: Orchestrace (Flow) `[pokročilé]`

Navrhni a nakonfiguruj Keboola Flow, který orchestruje celý pipeline:

- Správné pořadí kroků (dependency)
- Paralelní spuštění tam, kde je to možné
- Notifikace při selhání (e-mail nebo Slack webhook / stačí navrhnout)
- Schedule: denní spuštění v **6:00 UTC**

V komentáři vysvětli proč jsi zvolil/a toto pořadí a kde jsi identifikoval/a možnost paralelizace.

> **Tip:** Přemýšlej o datových závislostech - co musí proběhnout dřív, co může běžet souběžně.

**Odevzdat:** Nakonfigurovaný Flow v Keboola + písemné zdůvodnění (5–10 vět)

---

### Úkol 5: Datový Model & Dokumentace `[pokročilé]`

Navrhni vrstvený datový model pro tento use case. Popiš nebo nakresli:

- Jaké vrstvy by pipeline měla mít (raw / stage / mart nebo jiné) a co patří do každé
- Pojmenování bucketů a tabulek (konvence)
- Jaké tabulky by byly exponovány do BI nástroje (Metabase, Tableau…) a proč

> **Tip:** Nejsou správné a špatné odpovědi - chceme vidět, jak přemýšlíš o architektuře.

**Odevzdat:** Dokument nebo diagram (PDF / PNG / Notion / markdown)

---

## Co hodnotíme

| Oblast                     | Váha | Co sledujeme                                     |
| -------------------------- | ---- | ------------------------------------------------ |
| SQL kvalita                | 20 % | Čitelnost, CTE, window funkce správně            |
| Keboola znalost            | 20 % | Bloky, buckety, naming, Storage patterns         |
| Data quality thinking      | 15 % | Identifikoval/a problémy, navrhl/a řešení        |
| Python transformace        | 20 % | Čistý kód, error handling, Keboola I/O pattern   |
| Architektura & orchestrace | 15 % | Logické pořadí, paralelizace, dependency         |
| Komunikace výsledků        | 10 % | Umí vysvětlit rozhodnutí, datový model má logiku |

---

## Podmínky
- **Přístup:** dostaneš credentials k Keboola projektu (read/write, vlastní workspace)
- **Odevzdání:** vše v Keboola projektu + stručný textový soubor s popisem datového modelu
- Pokud něco nestihneš, napiš co bys dělal/a dál - postup je stejně důležitý jako výsledek
