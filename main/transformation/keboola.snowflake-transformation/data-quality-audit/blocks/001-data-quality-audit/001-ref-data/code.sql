-- =====================================================================
-- BLOK 1 / Reference data
--   1) ref_allowed_status
--   2) ref_allowed_age_group   
--   3) issue_catalog           
-- =====================================================================

-- allowed values
CREATE OR REPLACE TABLE "ref_allowed_status" AS
SELECT * FROM VALUES
    ('completed'),
    ('cancelled'),
    ('returned')
AS v(status);

CREATE OR REPLACE TABLE "ref_allowed_age_group" AS
SELECT * FROM VALUES
    ('18-24'),
    ('25-34'),
    ('35-44'),
    ('45-54'),
    ('55+')
AS v(age_group);

-- Catalog
-- Key: (table_name, issue_type)
CREATE OR REPLACE TABLE "issue_catalog" AS
SELECT * FROM VALUES
    ------ orders -------------------------------------------------------
    ('orders','null_in_key_order_id',
        'order_id je NULL – objednávku nelze jednoznačně identifikovat.',
        'Dohledat u zdroje, doplnit nebo odfiltrovat při loadingu.'),
    ('orders','null_in_key_user_id',
        'user_id je NULL – objednávku nelze přiřadit k zákazníkovi.',
        'Doplnit ze zdroje, případně mapovat na guest user.'),
    ('orders','null_in_key_product_id',
        'product_id je NULL – nelze přiřadit produkt.',
        'Doplnit ze zdroje, jinak řádek vyloučit z produktových reportů.'),
    ('orders','null_order_date',
        'order_date je NULL – objednávka nemá datum.',
        'Doplnit z logu transakce nebo z created_at.'),
    ('orders','duplicate_order_id',
        'order_id se v tabulce opakuje – primární klíč není unikátní.',
        'Deduplikovat (ROW_NUMBER() podle order_date DESC) nebo opravit u zdroje.'),
    ('orders','null_status',
        'Status je NULL – nevíme, ve které fázi objednávka je.',
        'Doplnit default (např. ''new'') nebo opravit u zdroje.'),
    ('orders','invalid_status',
        'Status mimo povolený číselník (completed / cancelled / returned) a zároveň mimo známé jazykové aliasy.',
        'Sjednotit s reálným číselníkem. Povolené hodnoty uprav v ref_allowed_status.'),
    ('orders','status_inconsistency',
        'Status má nekonzistentní zápis – buď odlišné psaní písmen či mezery (např. COMPLETED, Completed vs. completed), nebo známý jazykový alias („kompletní" jako ekvivalent „completed").',
        'Sjednotit u zdroje na jednotný anglický číselník v lowercase. V ETL dočasně aplikovat LOWER(TRIM(status)) a v cleansing vrstvě přemapovat známé aliasy (kompletní → completed).'),
    ('orders','completed_zero_or_null_revenue',
        'Objednávka má status completed, ale revenue_czk je 0 nebo NULL.',
        'Ověřit u zdroje; případně přepočítat z quantity * price * (1 - discount_pct).'),
    ('orders','quantity_le_zero',
        'quantity je 0 nebo záporné – nedává obchodní smysl.',
        'Opravit u zdroje; vratky řešit přes status, ne přes záporné množství.'),
    ('orders','discount_out_of_range',
        'discount_pct mimo rozsah 0–1 (data jsou v desetinné stupnici).',
        'Pokud má být v procentech, převést u zdroje (*100). Jinak ponechat rozsah 0–1.'),
    ('orders','fk_user_id_not_in_users',
        'orders.user_id neexistuje v tabulce users.',
        'Doplnit chybějící uživatele do users, nebo ošetřit přes LEFT JOIN + flag.'),
    ('orders','fk_product_id_not_in_products',
        'orders.product_id neexistuje v tabulce products.',
        'Doplnit produkt do products, nebo přidat „unknown product" řádek.'),
    ------ products -----------------------------------------------------
    ('products','null_in_key_product_id',
        'product_id je NULL – produkt nelze identifikovat.',
        'Doplnit ze zdroje nebo vyřadit řádek.'),
    ('products','duplicate_product_id',
        'product_id se opakuje – primární klíč není unikátní.',
        'Deduplikovat (preferovat is_active = 1 a nejnovější záznam).'),
    ('products','price_le_zero',
        'price_czk je 0, záporná nebo NULL.',
        'Opravit u zdroje; zboží zdarma řešit samostatným flagem.'),
    ('products','missing_product_name',
        'Chybí product_name (NULL nebo prázdný řetězec).',
        'Doplnit z katalogu produktů.'),
    ('products','missing_category',
        'Chybí kategorie produktu.',
        'Doplnit z katalogu, případně zařadit do „Uncategorized".'),
    ('products','margin_out_of_range',
        'margin_pct mimo rozsah 0–1 (data jsou v desetinné stupnici).',
        'Zarovnat horní limit s byznysem (např. 0.9). Aktuální reálné max v datech ≈ 0.44.'),
    ------ users --------------------------------------------------------
    ('users','null_in_key_user_id',
        'user_id je NULL – uživatele nelze identifikovat.',
        'Doplnit ze zdroje nebo vyřadit.'),
    ('users','duplicate_user_id',
        'user_id se opakuje – primární klíč není unikátní.',
        'Deduplikovat (preferovat nejnovější registered_at).'),
    ('users','missing_country',
        'Chybí country – nelze segmentovat podle země.',
        'Doplnit, případně zařadit do „Unknown".'),
    ('users','missing_acquisition_channel',
        'Chybí acquisition_channel – nelze měřit účinnost akvizice.',
        'Doplnit z marketingových zdrojů, jinak „Unknown".'),
    ('users','missing_registered_at',
        'Chybí registered_at – nelze počítat délku vztahu se zákazníkem.',
        'Doplnit ze zdroje (event log, CRM).'),
    ('users','missing_age_group',
        'Chybí age_group – nelze provádět věkovou segmentaci.',
        'Doplnit z registračního formuláře, jinak označit jako „Unknown".'),
    ('users','invalid_age_group_format',
        'age_group neodpovídá očekávanému číselníku (18-24, 25-34, 35-44, 45-54, 55+).',
        'Sjednotit s katalogem hodnot. Povolené hodnoty uprav v ref_allowed_age_group.')
AS v(table_name, issue_type, description, recommended_fix);
