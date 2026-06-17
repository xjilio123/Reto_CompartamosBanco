# 🚀 Reto Data Engineering - Compartamos Banco

Este proyecto automatiza un pipeline de datos completo (ETL) que procesa información de clientes, productos y ventas de la empresa, estructurando un modelo analítico seguro y listo para la toma de decisiones.

---

## 💻 Entorno Tecnológico
* **Base de Datos:** Microsoft SQL Server
* **Herramienta de Gestión:** SQL Server Management Studio 22 (SSMS)
* **Lenguaje de Orquestación:** Python 3.13

---

## 🛠️ Estructura del Proyecto

El repositorio está organizado de la siguiente manera:
* **`datos/`**: Carpeta local con los archivos CSV originales (`customers.csv`, `products.csv`, `orders.csv`).
* **`main.py`**: El orquestador maestro. Ejecuta todo el pipeline de principio a fin con un solo comando.
* **`scripts/`**:
    * `1_ingesta_raw.py`: Carga los archivos CSV crudos hacia la base de datos en SQL Server.
    * `2_limpieza_stage.sql`: Aplica reglas de calidad (filtra solo Colombia, elimina duplicados, corrige cantidades vacías).
    * `3_tablas_finales.sql`: Crea el Modelo Estrella unificado centrado en la tabla **`fact_ventas`**.
    * `4_seguridad_pii.py`: Protege la información confidencial de las tablas finales.
    * `5_examen.sql`: Resuelve las preguntas analíticas y estadísticas solicitadas.

---

## 🔒 Gobierno de Datos y Seguridad (PII)

Para cumplir con las normativas de protección de datos, se identificaron y blindaron las siguientes columnas sensibles en la capa final:
1.  **Correo Electrónico (`email` en `dim_customers`)**: Aplicamos un hasheo criptográfico **SHA-256**. Es irreversible, protegiendo la identidad del cliente.
2.  **Tarjeta de Crédito (`credit_card_last4` en `fact_ventas`)**: Aplicamos un **enmascaramiento parcial** convirtiendo el texto al formato seguro `****1234` para auditorías sin exponer el medio de pago.

---

## 🏃‍♂️ Cómo Ejecutar el Proyecto

1. Configura tu servidor local en el archivo `main.py` (`JoaquinCR\SQLEXPRESS`).
2. Abre la terminal en la raíz del proyecto.
3. Ejecuta el siguiente comando único para correr todo el flujo automáticamente:

```bash
python main.py