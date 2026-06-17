-- ============================================================================
-- FASE 3: MODELO ESTRELLA (CAPA ANALYTICS) - TABLAS FINALES
-- Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
-- MODIFICACIÓN: Tablón Unificado 'fact_ventas' en lugar de hechos separados.
-- ============================================================================

-- Control de Idempotencia: Eliminar tablas respetando las restricciones de integridad referencial
IF OBJECT_ID('dbo.fact_ventas', 'U') IS NOT NULL DROP TABLE dbo.fact_ventas;
IF OBJECT_ID('dbo.dim_customers', 'U') IS NOT NULL DROP TABLE dbo.dim_customers;
IF OBJECT_ID('dbo.dim_products', 'U') IS NOT NULL DROP TABLE dbo.dim_products;

-- ----------------------------------------------------------------------------
-- 1. CREACIÓN DE LA DIMENSIÓN: dim_customers
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.dim_customers (
    customer_id INT PRIMARY KEY,                 -- Llave Primaria (ID Único de Cliente)
    first_name VARCHAR(150),                     -- Nombre en Mayúsculas
    last_name VARCHAR(150),                      -- Apellido en Mayúsculas
    email VARCHAR(255),                          -- Correo Electrónico (A ser protegido con PII en Fase 4)
    phone VARCHAR(50),                           -- Teléfono de Contacto
    city VARCHAR(100),                           -- Ciudad de Residencia
    country VARCHAR(100),                        -- País Filtrado (Únicamente COLOMBIA)
    age INT,                                     -- Edad Estandarizada
    registration_date DATETIME,                  -- Fecha de Registro Original más Antigua
    loyalty_tier VARCHAR(100),                   -- Nivel de Lealtad (Estandarizado o 'NO DETERMINADO')
    fecha_carga DATETIME DEFAULT GETDATE()       -- Auditoría de carga analítica
);

-- Ingesta limpia desde STAGE
INSERT INTO dbo.dim_customers (customer_id, first_name, last_name, email, phone, city, country, age, registration_date, loyalty_tier)
SELECT customer_id, first_name, last_name, email, phone, city, country, age, registration_date, loyalty_tier
FROM dbo.stg_customers;

-- ----------------------------------------------------------------------------
-- 2. CREACIÓN DE LA DIMENSIÓN: dim_products
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.dim_products (
    product_id INT PRIMARY KEY,                  -- Llave Primaria (ID Único de Producto)
    product_name VARCHAR(255),                   -- Nombre de Producto en Mayúsculas
    category VARCHAR(150),                       -- Categoría del Catálogo
    price_usd DECIMAL(10,2),                     -- Precio de Venta Unitario Estandarizado
    cost_usd DECIMAL(10,2),                      -- Costo de Adquisición Estandarizado
    stock_units INT,                             -- Unidades Disponibles en Inventario
    supplier VARCHAR(150),                       -- Proveedor Formateado o 'NO DETERMINADO'
    active VARCHAR(50),                          -- Estado Binarizado ('ACTIVO' / 'INACTIVO')
    fecha_carga DATETIME DEFAULT GETDATE()
);

-- Ingesta limpia desde STAGE
INSERT INTO dbo.dim_products (product_id, product_name, category, price_usd, cost_usd, stock_units, supplier, active)
SELECT product_id, product_name, category, price_usd, cost_usd, stock_units, supplier, active
FROM dbo.stg_products;

-- ----------------------------------------------------------------------------
-- 3. CREACIÓN DEL TABLÓN UNIFICADO DE HECHOS: fact_ventas
-- ----------------------------------------------------------------------------
CREATE TABLE dbo.fact_ventas (
    order_id INT,                                -- ID de la Orden de Venta
    customer_id INT,                             -- Llave Foránea hacia dim_customers
    product_id INT,                              -- Llave Foránea hacia dim_products
    quantity INT,                                -- Unidades Vendidas (Calculadas o Corregidas)
    unit_price_usd DECIMAL(10,2),                -- Precio Unitario cobrado
    total_amount_usd DECIMAL(10,2),              -- Monto Total Bruto de la Transacción
    discount_pct DECIMAL(5,2),                   -- Porcentaje de Descuento Aplicado (0.00 a 100.00)
    -- Métrica Calculada Analítica: Monto neto real ingresado tras el descuento
    net_amount_usd AS (total_amount_usd * (1.00 - (discount_pct / 100.00))),
    order_date DATETIME,                         -- Fecha de Captura del Pedido
    ship_date DATETIME,                          -- Fecha de Envío de Mercadería (o NULL si fue inconsistente)
    status VARCHAR(100),                         -- Estado de la Venta Estandarizado
    payment_method VARCHAR(100),                 -- Medio de Pago Autorizado
    credit_card_last4 VARCHAR(50),               -- Registro de Tarjeta (A ser enmascarado en Fase 4)
    fecha_carga DATETIME DEFAULT GETDATE(),
    
    -- Restricciones de Integridad Referencial Requeridas para un Modelo Estrella Robusto
    CONSTRAINT FK_fact_ventas_customer FOREIGN KEY (customer_id) REFERENCES dbo.dim_customers(customer_id),
    CONSTRAINT FK_fact_ventas_product FOREIGN KEY (product_id) REFERENCES dbo.dim_products(product_id)
);

-- Ingesta Cruzada con Validación de Integridad Referencial NAtiva (Garantiza que existan en DIM)
INSERT INTO dbo.fact_ventas (order_id, customer_id, product_id, quantity, unit_price_usd, total_amount_usd, discount_pct, order_date, ship_date, status, payment_method, credit_card_last4)
SELECT 
    o.order_id,
    o.customer_id,
    o.product_id,
    o.quantity,
    o.unit_price_usd,
    o.total_amount_usd,
    o.discount_pct,
    o.order_date,
    o.ship_date,
    o.status,
    o.payment_method,
    o.credit_card_last4
FROM dbo.stg_orders o
INNER JOIN dbo.dim_customers c ON o.customer_id = c.customer_id -- Valida que el cliente exista y sea de Colombia
INNER JOIN dbo.dim_products p ON o.product_id = p.product_id;   -- Valida que el producto exista en el catálogo