-- ============================================================================
-- FASE 5: EXAMEN SQL - RESOLUCIÓN DE PREGUNTAS ANALÍTICAS DE NEGOCIO
-- Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
-- MODELO OPTIMIZADO: Operaciones directas sobre el tablón unificado 'fact_ventas'
-- ============================================================================

USE Compartamos_Banco2;
GO

-- ----------------------------------------------------------------------------
-- 📊 P1. TOP 3 CLIENTES CON MAYOR NÚMERO DE PEDIDOS EN EL ÚLTIMO TRIMESTRE
-- ----------------------------------------------------------------------------
-- Justificación: Se detecta dinámicamente la fecha máxima real en el tablón unificado
-- de ventas para calcular el inicio del último trimestre. Cuenta órdenes únicas agrupadas
-- por cliente de Colombia, incluyendo los nombres cruzados desde la dimensión.

WITH RangoUltimoTrimestre AS (
    SELECT 
        MAX(order_date) AS FechaMaxima,
        DATEADD(quarter, DATEDIFF(quarter, 0, MAX(order_date)), 0) AS InicioTrimestreMaximo
    FROM dbo.fact_ventas
)
SELECT TOP 3
    v.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS nombre_completo,
    COUNT(DISTINCT v.order_id) AS cantidad_pedidos
FROM dbo.fact_ventas v
INNER JOIN dbo.dim_customers c ON v.customer_id = c.customer_id -- Trae nombres limpios de clientes validados
CROSS JOIN RangoUltimoTrimestre r
WHERE v.order_date >= r.InicioTrimestreMaximo AND v.order_date <= r.FechaMaxima
GROUP BY v.customer_id, c.first_name, c.last_name
ORDER BY cantidad_pedidos DESC, nombre_completo ASC;


-- ----------------------------------------------------------------------------
-- 📊 P2. REVENUE MENSUAL POR CATEGORÍA DE PRODUCTO (ORDENADO DE MAYOR A MENOR)
-- ----------------------------------------------------------------------------
-- Justificación: Extrae el año y mes directamente de 'order_date'. Cruza con la dimension
-- 'dim_products' para extraer la categoría real del producto y calcula el revenue acumulado bruto.

SELECT 
    YEAR(v.order_date) AS [año],
    MONTH(v.order_date) AS [mes],
    p.category AS categoria,
    SUM(v.total_amount_usd) AS revenue_total
FROM dbo.fact_ventas v
INNER JOIN dbo.dim_products p ON v.product_id = p.product_id -- Cruce con catálogo estandarizado
GROUP BY YEAR(v.order_date), MONTH(v.order_date), p.category
ORDER BY revenue_total DESC;


-- ----------------------------------------------------------------------------
-- 📊 P3. DETECCIÓN DE PEDIDOS ANÓMALOS (OUTLIERS CON Z-SCORE > 2.00)
-- ----------------------------------------------------------------------------
-- Justificación: Implementación de fórmulas estadísticas directas en SQL Server. Se evalúa
-- el total_amount_usd de cada pedido comparándolo contra el promedio y la desviación estándar
-- estándar poblacional (STDEV) global del tablón de hechos para aislar comportamientos atípicos.

WITH EstadisticasVentas AS (
    SELECT 
        AVG(total_amount_usd) AS promedio_global,
        STDEV(total_amount_usd) AS desviacion_estandar_global
    FROM dbo.fact_ventas
),
CalculoZScore AS (
    SELECT 
        v.order_id,
        v.customer_id,
        v.total_amount_usd,
        -- Fórmula estadística estándar: (Valor - Promedio) / Desviación Estándar
        (v.total_amount_usd - e.promedio_global) / NULLIF(e.desviacion_estandar_global, 0) AS z_score
    FROM dbo.fact_ventas v
    CROSS JOIN EstadisticasVentas e
)
SELECT 
    order_id,
    customer_id,
    total_amount_usd,
    ROUND(z_score, 4) AS z_score
FROM CalculoZScore
WHERE z_score > 2.00 -- Filtro de 2 desviaciones estándar superiores solicitado por rúbrica
ORDER BY z_score DESC;