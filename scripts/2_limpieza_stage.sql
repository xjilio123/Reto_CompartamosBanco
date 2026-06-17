-- ============================================================================
-- FASE 2: CAPA STAGE - REGLAS DE CALIDAD, TRATAMIENTO DE OUTLIERS Y LIMPIEZA
-- Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
-- ============================================================================

-- Control de Idempotencia: Elimina tablas previas para permitir ejecuciones infinitas
IF OBJECT_ID('dbo.stg_customers', 'U') IS NOT NULL DROP TABLE dbo.stg_customers;
IF OBJECT_ID('dbo.stg_products', 'U') IS NOT NULL DROP TABLE dbo.stg_products;
IF OBJECT_ID('dbo.stg_orders', 'U') IS NOT NULL DROP TABLE dbo.stg_orders;

-- ----------------------------------------------------------------------------
-- 1. TRANSFRMACIÓN Y LIMPIEZA: stg_customers
-- ----------------------------------------------------------------------------
-- Justificación: Casteo manual eliminando comillas residuales. Filtrado estricto 
-- por 'COLOMBIA'. Deduplicación por customer_id priorizando el registro más antiguo.
WITH ClientesProcesados AS (
    SELECT 
        TRY_CAST(REPLACE(REPLACE(customer_id, '"', ''), ' ', '') AS INT) AS customer_id,
        UPPER(TRIM(REPLACE(first_name, '"', ''))) AS first_name,
        UPPER(TRIM(REPLACE(last_name, '"', ''))) AS last_name,
        UPPER(TRIM(REPLACE(email, '"', ''))) AS email,
        TRIM(REPLACE(phone, '"', '')) AS phone,
        UPPER(TRIM(REPLACE(city, '"', ''))) AS city,
        UPPER(TRIM(REPLACE(country, '"', ''))) AS country,
        -- Tratamiento de edades imposibles
        CASE 
            WHEN TRY_CAST(REPLACE(age, '"', '') AS INT) < 0 OR TRY_CAST(REPLACE(age, '"', '') AS INT) > 120 THEN NULL 
            ELSE TRY_CAST(REPLACE(age, '"', '') AS INT) 
        END AS age,
        -- Estandarización de formato de separadores en fechas
        TRY_CAST(REPLACE(REPLACE(registration_date, '"', ''), '/', '-') AS DATETIME) AS registration_date,
        -- Imputación por defecto para loyalty_tier inválidos o vacíos
        CASE 
            WHEN loyalty_tier IS NULL OR TRIM(REPLACE(loyalty_tier, '"', '')) = '' OR TRIM(REPLACE(loyalty_tier, '"', '')) = 'NULL' THEN 'NO DETERMINADO'
            ELSE UPPER(TRIM(REPLACE(loyalty_tier, '"', '')))
        END AS loyalty_tier,
        -- Regla de negocio: Conservar la fecha de registro más antigua en duplicados
        ROW_NUMBER() OVER (
            PARTITION BY TRY_CAST(REPLACE(REPLACE(customer_id, '"', ''), ' ', '') AS INT) 
            ORDER BY TRY_CAST(REPLACE(REPLACE(registration_date, '"', ''), '/', '-') AS DATETIME) ASC
        ) AS rn
    FROM dbo.raw_customers
)
SELECT 
    customer_id, first_name, last_name, email, phone, city, country, age, registration_date, loyalty_tier,
    GETDATE() AS fecha_actualizacion_stage
INTO dbo.stg_customers
FROM ClientesProcesados
WHERE rn = 1 
  AND customer_id IS NOT NULL
  AND country = 'COLOMBIA'
  AND NOT (first_name IS NULL AND last_name IS NULL AND email IS NULL);


-- ----------------------------------------------------------------------------
-- 2. TRANSFORMACIÓN Y LIMPIEZA: stg_products
-- ----------------------------------------------------------------------------
-- Justificación: Identificadores enteros únicos, imputación de costos/precios/stocks 
-- inválidos a 0, validación del patrón de proveedor y binarización de estado activo.
WITH ProductosProcesados AS (
    SELECT 
        TRY_CAST(REPLACE(REPLACE(product_id, '"', ''), ' ', '') AS INT) AS product_id,
        UPPER(TRIM(REPLACE(product_name, '"', ''))) AS product_name,
        UPPER(TRIM(REPLACE(category, '"', ''))) AS category,
        -- Reemplazo de precios inválidos o negativos a 0.00
        CASE 
            WHEN TRY_CAST(REPLACE(price_usd, '"', '') AS DECIMAL(10,2)) < 0 THEN 0.00
            ELSE ISNULL(TRY_CAST(REPLACE(price_usd, '"', '') AS DECIMAL(10,2)), 0.00)
        END AS price_usd,
        -- Reemplazo de costos inválidos o negativos a 0.00
        CASE 
            WHEN TRY_CAST(REPLACE(cost_usd, '"', '') AS DECIMAL(10,2)) < 0 THEN 0.00
            ELSE ISNULL(TRY_CAST(REPLACE(cost_usd, '"', '') AS DECIMAL(10,2)), 0.00)
        END AS cost_usd,
        -- Reemplazo de stocks vacíos o negativos a 0
        CASE 
            WHEN TRY_CAST(REPLACE(stock_units, '"', '') AS INT) < 0 THEN 0
            ELSE ISNULL(TRY_CAST(REPLACE(stock_units, '"', '') AS INT), 0)
        END AS stock_units,
        -- Validación de formato 'PROVEEDOR [LETRA]'
        CASE 
            WHEN UPPER(TRIM(REPLACE(supplier, '"', ''))) LIKE 'PROVEEDOR [A-Z]' THEN UPPER(TRIM(REPLACE(supplier, '"', '')))
            ELSE 'NO DETERMINADO'
        END AS supplier,
        -- Reducción estricta del flag activo a dos únicos valores
        CASE 
            WHEN UPPER(TRIM(REPLACE(active, '"', ''))) IN ('1', 'TRUE', 'ACTIVO', 'YES') THEN 'ACTIVO'
            ELSE 'INACTIVO'
        END AS active,
        ROW_NUMBER() OVER (
            PARTITION BY TRY_CAST(REPLACE(REPLACE(product_id, '"', ''), ' ', '') AS INT) 
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM dbo.raw_products
)
SELECT 
    product_id, product_name, category, price_usd, cost_usd, stock_units, supplier, active,
    GETDATE() AS fecha_actualizacion_stage
INTO dbo.stg_products
FROM ProductosProcesados
WHERE rn = 1 AND product_id IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 3. TRANSFORMACIÓN Y LIMPIEZA: stg_orders
-- ----------------------------------------------------------------------------
-- Justificación: Identificadores numéricos obligatorios, estandarización de estados y 
-- métodos de pago. Implementación del recálculo matemático de la cantidad cuando es inválida.
WITH OrdenesProcesadas AS (
    SELECT 
        TRY_CAST(REPLACE(REPLACE(order_id, '"', ''), ' ', '') AS INT) AS order_id,
        TRY_CAST(REPLACE(REPLACE(customer_id, '"', ''), ' ', '') AS INT) AS customer_id,
        TRY_CAST(REPLACE(REPLACE(product_id, '"', ''), ' ', '') AS INT) AS product_id,
        
        TRY_CAST(REPLACE(unit_price_usd, '"', '') AS DECIMAL(10,2)) AS unit_price_usd,
        TRY_CAST(REPLACE(total_amount_usd, '"', '') AS DECIMAL(10,2)) AS total_amount_usd,
        
        -- Regla Solicitada: Recálculo de cantidad en base a total_amount_usd / unit_price_usd
        CASE 
            WHEN TRY_CAST(REPLACE(quantity, '"', '') AS INT) <= 0 
                 OR TRY_CAST(REPLACE(quantity, '"', '') AS INT) IS NULL THEN 
                 TRY_CAST((TRY_CAST(REPLACE(total_amount_usd, '"', '') AS DECIMAL(10,2)) / 
                 NULLIF(TRY_CAST(REPLACE(unit_price_usd, '"', '') AS DECIMAL(10,2)), 0)) AS INT)
            ELSE TRY_CAST(REPLACE(quantity, '"', '') AS INT)
        END AS quantity,
        
        TRY_CAST(REPLACE(REPLACE(order_date, '"', ''), '/', '-') AS DATETIME) AS order_date,
        TRY_CAST(REPLACE(REPLACE(ship_date, '"', ''), '/', '-') AS DATETIME) AS ship_date,
        
        CASE 
            WHEN status IS NULL OR TRIM(REPLACE(status, '"', '')) IN ('', 'NULL') THEN 'NO DETERMINADO'
            ELSE UPPER(TRIM(REPLACE(status, '"', '')))
        END AS status,
        
        CASE 
            WHEN payment_method IS NULL OR TRIM(REPLACE(payment_method, '"', '')) IN ('', 'NULL') THEN 'NO DETERMINADO'
            ELSE UPPER(TRIM(REPLACE(payment_method, '"', '')))
        END AS payment_method,
        
        -- Tratamiento de anomalías en porcentajes de descuento
        CASE 
            WHEN TRY_CAST(REPLACE(discount_pct, '"', '') AS DECIMAL(5,2)) > 100.00 THEN 100.00
            WHEN TRY_CAST(REPLACE(discount_pct, '"', '') AS DECIMAL(5,2)) < 0.00 THEN 0.00
            ELSE ISNULL(TRY_CAST(REPLACE(discount_pct, '"', '') AS DECIMAL(5,2)), 0.00)
        END AS discount_pct,
        
        TRIM(REPLACE(credit_card_last4, '"', '')) AS credit_card_last4,
        
        ROW_NUMBER() OVER (
            PARTITION BY TRY_CAST(REPLACE(REPLACE(order_id, '"', ''), ' ', '') AS INT) 
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM dbo.raw_orders
)
SELECT 
    order_id, customer_id, product_id, quantity, unit_price_usd, total_amount_usd,
    order_date,
    -- Regla de Negocio: Si ship_date es menor a order_date, se anula marcando NULL
    CASE 
        WHEN ship_date < order_date THEN NULL 
        ELSE ship_date 
    END AS ship_date,
    status, payment_method, discount_pct, credit_card_last4,
    GETDATE() AS fecha_actualizacion_stage
INTO dbo.stg_orders
FROM OrdenesProcesadas
WHERE rn = 1 
  AND order_id IS NOT NULL;