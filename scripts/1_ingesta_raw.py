# ============================================================================
# FASE 1: INGESTA DE DATOS (ZONA RAW) - PIPELINE MAESTRO
# Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
# ============================================================================

import os
import urllib
import pandas as pd
from sqlalchemy import create_engine

def ingestar_datos_raw():
    print("\n==================================================================")
    print("🚀 INICIANDO FASE 1: INGESTA DE DATOS EN ENTORNOS AUTOMATIZADOS")
    print("==================================================================")
    
    # 1. Configuración centralizada de rutas absolutas
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    datos_dir = os.path.join(base_dir, "datos")
    
    # 2. Configuración de la cadena de conexión a SQL Server (Credenciales del reto)
    SERVER = r'JOAQUINCR\SQLEXPRESS'
    DATABASE = 'Compartamos_Banco2'
    
    connection_string = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;"
    params = urllib.parse.quote_plus(connection_string)
    engine = create_engine(f"mssql+pyodbc:///?odbc_connect={params}")
    
    # 3. Escaneo dinámico y mapeo de los archivos CSV presentes en /datos
    if not os.path.exists(datos_dir) or not os.listdir(datos_dir):
        raise FileNotFoundError(f"❌ Error Crítico: La carpeta '/datos' está vacía o no existe en {datos_dir}")
        
    archivos_csv = [f for f in os.listdir(datos_dir) if f.endswith('.csv')]
    print(f"📦 Se detectaron {len(archivos_csv)} archivos listos para ingesta en /datos.")
    
    # 4. Iteración y carga defensiva hacia las tablas de la zona RAW
    for archivo in archivos_csv:
        ruta_completa = os.path.join(datos_dir, archivo)
        # Extraemos el nombre base del archivo para nombrar la tabla (ej: 'customers' -> 'raw_customers')
        nombre_base = os.path.splitext(archivo)[0].lower()
        nombre_tabla = f"raw_{nombre_base}"
        
        print(f"\n📖 Leyendo origen: {ruta_completa}...")
        
        # Estrategia adaptativa de Encoding para evitar caídas por caracteres especiales latinos
        try:
            df_raw = pd.read_csv(ruta_completa, encoding='utf-8', dtype=str)
        except UnicodeDecodeError:
            print("⚠️ Archivo no estructurado en UTF-8. Aplicando codificación alternativa (latin-1)...")
            df_raw = pd.read_csv(ruta_completa, encoding='latin-1', dtype=str)
            
        # Cargamos en formato String Puro (dtype=str) para asegurar que no se alteren los errores intencionales
        print(f"⏳ Volcando {len(df_raw)} registros en la tabla 'dbo.{nombre_tabla}'...")
        
        # Ingesta con reemplazo automático para garantizar idempotencia en la capa RAW
        df_raw.to_sql(
            name=nombre_tabla,
            con=engine,
            index=False,
            if_exists='replace',
            schema='dbo'
        )
        print(f"✅ Capa RAW: Tabla '{nombre_tabla}' cargada exitosamente.")

    print("\n==================================================================")
    print("🏆 FASE 1 COMPLETADA: Zona RAW cargada y disponible en SSMS.")
    print("==================================================================")

if __name__ == "__main__":
    ingestar_datos_raw()