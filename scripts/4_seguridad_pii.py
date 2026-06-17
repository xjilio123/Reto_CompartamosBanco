# ============================================================================
# FASE 8: SEGURIDAD DE LA INFORMACIÓN (PII) - PROTECCIÓN CRIPTOGRÁFICA
# Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
# Técnicas: Hasheo SHA-256 (Email) y Enmascaramiento Dinámico (Tarjeta)
# ============================================================================

import os
import urllib
import hashlib
import pandas as pd
from sqlalchemy import create_engine, text

def proteger_datos_pii():
    print("\n==================================================================")
    print("🔒 INICIANDO FASE 8: GOBIERNO DE DATOS Y PROTECCIÓN DE PII")
    print("==================================================================")
    
    # 1. Conexión centralizada a SQL Server
    SERVER = r'JOAQUINCR\SQLEXPRESS'
    DATABASE = 'Compartamos_Banco2'
    
    connection_string = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;"
    params = urllib.parse.quote_plus(connection_string)
    engine = create_engine(f"mssql+pyodbc:///?odbc_connect={params}")
    
    with engine.begin() as conexion:
        # ---- CONTROL A: HASHING SHA-256 PARA DATA SENSIBLE DE CONTACTO (EMAIL) ----
        print("⏳ Extrayendo registros de 'dim_customers' para aplicar Hashing SHA-256...")
        df_clientes = pd.read_sql("SELECT customer_id, email FROM dbo.dim_customers", conexion)
        
        # Función anónima para hashear con SHA-256 de forma segura
        def aplicar_sha256(val):
            if pd.isna(val) or str(val).strip() == '' or str(val).upper() == 'NULL':
                return val
            # Estandariza a minúsculas, remueve espacios y cifra de forma irreversible
            return hashlib.sha256(str(val).strip().lower().encode('utf-8')).hexdigest()
        
        df_clientes['email_protegido'] = df_clientes['email'].apply(aplicar_sha256)
        
        # Actualización masiva eficiente en SQL Server
        print("💾 Impactando cambios anonimizados en la tabla 'dbo.dim_customers'...")
        for _, fila in df_clientes.iterrows():
            conexion.execute(
                text("UPDATE dbo.dim_customers SET email = :email WHERE customer_id = :id"),
                {"email": fila['email_protegido'], "id": int(fila['customer_id'])}
            )
        print("✅ Columna 'email' cifrada exitosamente con SHA-256.")
        
        # ---- CONTROL B: ENMASCARAMIENTO PARCIAL PARA DATA FINANCIERA (TARJETA) ----
        print("\n⏳ Extrayendo registros de 'fact_ventas' para enmascaramiento transaccional...")
        df_ventas = pd.read_sql("SELECT DISTINCT order_id, credit_card_last4 FROM dbo.fact_ventas", conexion)
        
        # Función anónima para formatear la tarjeta manteniendo auditoría (ej: ****1234)
        def enmascarar_tarjeta(val):
            val_str = str(val).strip()
            if pd.isna(val) or val_str == '' or val_str.upper() == 'NULL':
                return '****0000' # Valor seguro por defecto si viene huérfano
            
            # Si solo vienen los 4 dígitos crudos, los concatena al patrón seguro
            if len(val_str) <= 4:
                return f"****{val_str}"
            else:
                # Si viene el número completo, extrae limpiamente los últimos 4 caracteres
                return f"****{val_str[-4:]}"
                
        df_ventas['tarjeta_enmascarada'] = df_ventas['credit_card_last4'].apply(enmascarar_tarjeta)
        
        # Actualización masiva eficiente en el tablón de hechos
        print("💾 Aplicando máscara regulatoria en la tabla 'dbo.fact_ventas'...")
        for _, fila in df_ventas.iterrows():
            conexion.execute(
                text("UPDATE dbo.fact_ventas SET credit_card_last4 = :mask WHERE order_id = :id"),
                {"mask": fila['tarjeta_enmascarada'], "id": int(fila['order_id'])}
            )
        print("✅ Columna 'credit_card_last4' enmascarada exitosamente con patrón (****XXXX).")

    print("\n==================================================================")
    print("🏆 FASE 8 COMPLETADA: Tablas finales protegidas y listas para producción.")
    print("==================================================================")

if __name__ == "__main__":
    proteger_datos_pii()