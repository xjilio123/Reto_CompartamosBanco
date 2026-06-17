# ============================================================================
# ORQUESTRADOR MAESTRO CENTRAL FINAL AUTOMATIZADO - `main.py`
# Servidor: JoaquinCR\SQLEXPRESS | Base de Datos: Compartamos_Banco2
# ============================================================================

import os
import re
import urllib
import importlib.util
from sqlalchemy import create_engine, text

def importar_modulo_dinamico(ruta_relativa, nombre_funcion):
    """Carga módulos dinámicamente superando la restricción de nombres con números en Python."""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    ruta_absoluta = os.path.join(base_dir, ruta_relativa)
    
    if not os.path.exists(ruta_absoluta):
        raise FileNotFoundError(f"❌ No se encontró el script en: {ruta_absoluta}")
        
    especificacion = importlib.util.spec_from_file_location("modulo_dinamico", ruta_absoluta)
    modulo = importlib.util.module_from_spec(especificacion)
    especificacion.loader.exec_module(modulo)
    return getattr(modulo, nombre_funcion)

def ejecutar_script_sql(ruta_sql, engine, mensaje_fase):
    """Lee y ejecuta bloques de SQL dividiendo estrictamente por líneas independientes de GO."""
    print(f"\n⏳ Ejecutando: {mensaje_fase}...")
    if not os.path.exists(ruta_sql):
        raise FileNotFoundError(f"❌ Error: No se encontró el archivo SQL en {ruta_sql}")
        
    with open(ruta_sql, 'r', encoding='utf-8') as archivo:
        contenido_sql = archivo.read()
    
    # Expresión regular que detecta 'GO' solo si es una palabra completa en su propia línea
    # Ignora 'GO' si está dentro de CATEGORIA, GOVERMENT, u otras palabras.
    bloques_sql = re.split(r'(?i)^\s*GO\s*$', contenido_sql, flags=re.MULTILINE)
    
    with engine.connect() as conexion:
        transaccion = conexion.begin()
        try:
            for bloque in bloques_sql:
                lineas_limpias = []
                for linea in bloque.splitlines():
                    # Conservar líneas lógicas y saltar comentarios conflictivos si los hay
                    if linea.strip().startswith('--') and any(w in linea.upper() for w in ['CATEGORIA', 'PRODUCTO', 'GO']):
                        continue
                    lineas_limpias.append(linea)
                
                bloque_final = "\n".join(lineas_limpias).strip()
                
                if bloque_final:
                    conexion.execute(text(bloque_final))
            transaccion.commit()
            print(f"✅ Completado con éxito: {mensaje_fase}")
        except Exception as e:
            transaccion.rollback()
            print(f"❌ Fallo crítico en el bloque SQL de: {mensaje_fase}")
            raise e

def orquestar_pipeline_completo():
    print("==================================================================")
    print("🛸 INICIANDO PIPELINE UNIFICADO Y AUTOMATIZADO - COMPARTAMOS BANCO")
    print("==================================================================")
    
    base_dir = os.path.dirname(os.path.abspath(__file__))
    scripts_dir = os.path.join(base_dir, "scripts")
    
    # Rutas físicas de la secuencia SQL
    ruta_stage = os.path.join(scripts_dir, "2_limpieza_stage.sql")
    ruta_analytics = os.path.join(scripts_dir, "3_tablas_finales.sql")
    ruta_examen = os.path.join(scripts_dir, "5_examen.sql")
    
    # Importación de los módulos Python
    ingestar_datos_raw = importar_modulo_dinamico("scripts/1_ingesta_raw.py", "ingestar_datos_raw")
    proteger_datos_pii = importar_modulo_dinamico("scripts/4_seguridad_pii.py", "proteger_datos_pii")
    
    # Credenciales y conexión
    SERVER = r'JOAQUINCR\SQLEXPRESS'
    DATABASE = 'Compartamos_Banco2'
    
    connection_string = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;"
    params = urllib.parse.quote_plus(connection_string)
    engine = create_engine(f"mssql+pyodbc:///?odbc_connect={params}")
    
    try:
        # FASE 1: Ingesta RAW (Python)
        ingestar_datos_raw()
        
        # FASE 2: Limpieza STAGE (SQL)
        ejecutar_script_sql(ruta_stage, engine, "Fase 2 - Limpieza y Calidad de Datos (STAGE)")
        
        # FASE 3: Modelo Estrella / Fact Ventas (SQL)
        ejecutar_script_sql(ruta_analytics, engine, "Fase 3 - Construcción de Modelo Estrella (ANALYTICS)")
        
        # FASE 4: Seguridad PII (Python)
        proteger_datos_pii()
        
        # FASE 5: Consultas de Negocio (SQL)
        ejecutar_script_sql(ruta_examen, engine, "Fase 5 - Resolución de Preguntas Analíticas (EXAMEN)")
        
        print("\n==================================================================")
        print("🏆 ¡PIPELINE INTEGRAL COMPLETADO DE PRINCIPIO A FIN CON ÉXITO!")
        print("==================================================================")
        
    except Exception as error_pipeline:
        print("\n🚨 Detención del Pipeline Maestro debido a inconsistencias:")
        print(f"Detalle del error: {str(error_pipeline)}")

if __name__ == "__main__":
    orquestar_pipeline_completo()