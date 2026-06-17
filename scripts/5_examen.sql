-- P1
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
INNER JOIN dbo.dim_customers c ON v.customer_id = c.customer_id
CROSS JOIN RangoUltimoTrimestre r
WHERE v.order_date >= r.InicioTrimestreMaximo AND v.order_date <= r.FechaMaxima
GROUP BY v.customer_id, c.first_name, c.last_name
ORDER BY cantidad_pedidos DESC, nombre_completo ASC;

GO

-- P2
SELECT 
    YEAR(v.order_date) AS [ano],
    MONTH(v.order_date) AS [mes],
    p.category AS categoria,
    SUM(v.total_amount_usd) AS revenue_total
FROM dbo.fact_ventas v
INNER JOIN dbo.dim_products p ON v.product_id = p.product_id
GROUP BY YEAR(v.order_date), MONTH(v.order_date), p.category
ORDER BY revenue_total DESC;

GO

-- P3
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
WHERE z_score > 2.00
ORDER BY z_score DESC;