-- ============================================================================
-- FASE 3: MODELO ESTRELLA (CAPA ANALYTICS) - TABLAS FINALES DEFINITIVAS
-- Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
-- REGLA EXCLUSIVA: Reemplazo de hechos separados por 'fact_ventas' unificado.
-- ============================================================================

-- Control de Idempotencia: Elimina las estructuras analíticas previas respetando las FKs
IF OBJECT_ID('dbo.fact_ventas', 'U') IS NOT NULL DROP TABLE dbo.fact_ventas;
IF OBJECT_ID('dbo.dim_customers', 'U') IS NOT NULL DROP TABLE dbo.dim_customers;
IF OBJECT_ID('dbo.dim_products', 'U') IS NOT NULL DROP TABLE dbo.dim_products;

-- ----------------------------------------------------------------------------
-- 1. DIMENSIÓN MAESTRA: dim_customers
-- ----------------------------------------------------------------------------
-- Contiene la información única y estandarizada de los clientes de Colombia.
CREATE TABLE dbo.dim_customers (
    customer_id INT PRIMARY KEY,                 -- Llave Primaria (Identificador Entero Único)
    first_name VARCHAR(150),                     -- Nombre Estandarizado en Mayúsculas
    last_name VARCHAR(150),                      -- Apellido Estandarizado en Mayúsculas
    email VARCHAR(255),                          -- Correo Electrónico (Pendiente a Hasheo SHA-256)
    phone VARCHAR(50),                           -- Teléfono Limpio
    city VARCHAR(100),                           -- Ciudad
    country VARCHAR(100),                        -- País de Origen (Validado: COLOMBIA)
    age INT,                                     -- Edad Filtrada sin valores imposibles
    registration_date DATETIME,                  -- Fecha de Registro más Antigua
    loyalty_tier VARCHAR(100),                   -- Categoría de Lealtad ('NO DETERMINADO' si fue inválido)
    fecha_carga DATETIME DEFAULT GETDATE()       -- Métrica de Auditoría de Carga
);

-- Ingesta de Datos desde la capa intermedia STAGE
INSERT INTO dbo.dim_customers (customer_id, first_name, last_name, email, phone, city, country, age, registration_date, loyalty_tier)
SELECT customer_id, first_name, last_name, email, phone, city, country, age, registration_date, loyalty_tier
FROM dbo.stg_customers;


-- ----------------------------------------------------------------------------
-- 2. DIMENSIÓN MAESTRA: dim_products
-- ----------------------------------------------------------------------------
-- Contiene el catálogo único de productos y sus métricas de costo/precio base.
CREATE TABLE dbo.dim_products (
    product_id INT PRIMARY KEY,                  -- Llave Primaria (Identificador Entero Único)
    product_name VARCHAR(255),                   -- Nombre de Producto en Mayúsculas
    category VARCHAR(150),                       -- Categoría del Catálogo
    price_usd DECIMAL(10,2),                     -- Precio Unitario Estandarizado (Default 0.00 si fue inválido)
    cost_usd DECIMAL(10,2),                      -- Costo Unitario Estandarizado (Default 0.00 si fue inválido)
    stock_units INT,                             -- Inventario Disponible (Default 0 si fue inválido)
    supplier VARCHAR(150),                       -- Proveedor Formateado o 'NO DETERMINADO'
    active VARCHAR(50),                          -- Estado Binarizado ('ACTIVO' / 'INACTIVO')
    fecha_carga DATETIME DEFAULT GETDATE()
);

-- Ingesta de Datos desde la capa intermedia STAGE
INSERT INTO dbo.dim_products (product_id, product_name, category, price_usd, cost_usd, stock_units, supplier, active)
SELECT product_id, product_name, category, price_usd, cost_usd, stock_units, supplier, active
FROM dbo.stg_products;


-- ----------------------------------------------------------------------------
-- 3. TABLÓN UNIFICADO DE HECHOS: fact_ventas
-- ----------------------------------------------------------------------------
-- Registra todas las transacciones monetarias y del negocio.
CREATE TABLE dbo.fact_ventas (
    order_id INT,                                -- Identificador de la Orden (INTEGER, No Nulo)
    customer_id INT,                             -- Llave Foránea vinculada a dim_customers (INTEGER)
    product_id INT,                              -- Llave Foránea vinculada a dim_products (INTEGER)
    quantity INT,                                -- Unidades Vendidas (Corregidas o recalculadas matemáticamente)
    unit_price_usd DECIMAL(10,2),                -- Precio Unitario cobrado (Numeric/Decimal)
    total_amount_usd DECIMAL(10,2),              -- Monto Total Bruto de la Transacción (Numeric/Decimal)
    discount_pct DECIMAL(5,2),                   -- Porcentaje de Descuento (Formateado entre 0.00 y 100.00)
    -- Métrica Calculada: Monto neto real ingresado tras sustraer el descuento
    net_amount_usd AS (total_amount_usd * (1.00 - (discount_pct / 100.00))),
    order_date DATETIME,                         -- Fecha de Captura del Pedido (Formato DATETIME)
    ship_date DATETIME,                          -- Fecha de Envío (Formato DATETIME, NULL si ship_date < order_date)
    status VARCHAR(100),                         -- Estado Estandarizado ('NO DETERMINADO' si fue inválido)
    payment_method VARCHAR(100),                 -- Medio de Pago ('NO DETERMINADO' si fue inválido)
    credit_card_last4 VARCHAR(50),               -- Registro de Tarjeta (Pendiente a Enmascaramiento)
    fecha_carga DATETIME DEFAULT GETDATE(),
    
    -- Restricciones de Integridad Referencial Fuertes para el Modelo Estrella
    CONSTRAINT FK_fact_ventas_customer FOREIGN KEY (customer_id) REFERENCES dbo.dim_customers(customer_id),
    CONSTRAINT FK_fact_ventas_product FOREIGN KEY (product_id) REFERENCES dbo.dim_products(product_id)
);

-- Ingesta Estratégica aplicando Validación de Existencia Absoluta (Integridad Referencial)
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
-- Regla de Negocio Crítica: "Los productos y clientes deben existir en sus respectivas tablas"
INNER JOIN dbo.dim_customers c ON o.customer_id = c.customer_id -- Excluye transacciones de clientes no registrados o que no son de Colombia
INNER JOIN dbo.dim_products p ON o.product_id = p.product_id;   -- Excluye transacciones con códigos de producto inexistentes