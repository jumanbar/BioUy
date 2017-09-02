<!---
Comentarios:  
  sudo apt install texlive-fonts-recommended,texlive-latex-extra,texlive-xetex  
    texlive-fonts-extra,texlive-lang-european,texlive-lang-spanish   
  pandoc -D latex > mitemplate.tex  
  # Modificaciones en mitemplate.tex, para que tengla la fuente que quiero...  
  pandoc -s -o ParaInformeVS.tex ParaInformeVS.md --template mitemplate.tex  
  pandoc -s -o ~/Procesamiento.pdf ParaInformeVS.md --template mitemplate.tex  
--> 

---
title: 'Determinación de ambientes (PPR) y Cartas SGM en padrones rurales de Uruguay: Procesamiento de los mapas'
author: Juan Manuel Barreneche  
colorlinks: blue
lang: es-AR
---

# Resumen

En este texto se describe el proceso de creación de las tablas que vinculan
Padrones Rurales con Ambientes y con Cartas SGM. Decidí meter el código todo
junto en este archivo, en vez de tener varios scripts separados, porque así se
conforma un tutorial. En el futuro tal vez sea mejor volver a muchos archivos
individuales.

De todas formas tener todo en un único texto ayuda a visualizar el hilo
conductor.

Nótese que acá hay código de SQL, GRASS y Bash, como mínimo.

El esquema del producto final está en el archivo `BioUy.xml` y se puede
visualizar en [https://www.draw.io](https://www.draw.io/). En la **Figura 1** se muestra el esquema
resultante.

![Modelo Entidad Relación](https://raw.githubusercontent.com/jumanbar/BioUy/master/Clean/BioUy.png "Esquema tablas")

\newpage

# Arreglos de la capa vectorial en PostgreSQL

Lo primero es hacer varios arreglos a la capa vectorial con los ambientes
(`ppr_biomes`). Se asume que dicha capa ya está importada dentro de la base.

Si hace falta importar la capa de nuevo, se puede hacer con QGIS: si se lo
conecta a la base PostgreSQL y con la interfaz gráfica se hace la importación.
Ver herramientas en el menú Database > DB Manager.

A continuación se muestra la secuencia de pasos para modificar la capa
vectorial/tabla para disminuir la cantidad de errores topológicos y complejidad.
Esto ayuda a que se pueda renderizar más rápidamente en QGIS y también a que
hayan menos errores cuando se haga la exportación a raster (GeoTIFF).

## 1. Respaldo de la tabla original

Para hacer modificaciones primero se respalda la capa/tabla original, bajo el
nombre `ppr_biomes_bak` (este puede ser el nombre dado a la capa al ser
importada desde QGIS). Luego se crea una copia que modificaremos, a la que
llamamos `ppr_biomes`:

```sql
CREATE TABLE ppr_biomes AS 
  SELECT id, geom FROM ppr_biomes_bak;
-- SELECT 48523

ALTER TABLE ppr_biomes ADD constraint pk_ppr_biomes_id PRIMARY KEY (id);

CREATE INDEX sidx_ppr_biomes_geom ON ppr_biomes USING GIST (geom);
```

## 2. Eliminar puntos repetidos

```sql
UPDATE ppr_biomes SET geom = ST_RemoveRepeatedPoints(geom);
```

> Query returned successfully: 48523 rows affected, 04:03 minutes execution
> time.

## 3. Simplificar geometrías

En PostgreSQL:

```sql
UPDATE ppr_biomes SET geom = ST_Simplify(geom, 1);
```

## 4. Multi -> Single polygons (ST_Dump)

```sql
CREATE TABLE ppr_biomes_dump AS
  SELECT id, (ST_Dump(geom)).* from ppr_biomes;
-- SELECT 6798778
```

## 5. Filtrar areas menores a una hectárea

### 5.1 Crear función filter_rings en PostgreSQL

Sirve para eliminar áreas pequeñas.

Author: Simon Greener
Web Page: http://www.spatialdbadvisor.com/postgis_tips_tricks/92/filtering-rings-in-polygon-postgis/

> Notes: This version of the function does not handle MultiPolygon geometries. I
> choosed it because it performs better. I'm not sure if his latest version
> (which does handle MultiPoligon) is really worse performing even when dealing
> with single Polygons.

Tiene una modificación del original: en vez de `> $2`, cambié por `>= $2`.

```sql
CREATE OR REPLACE FUNCTION filter_rings(geometry, DOUBLE PRECISION)
  RETURNS geometry AS
$BODY$
SELECT ST_MakePolygon((/* Get outer ring of polygon */
        SELECT ST_ExteriorRing(geom) AS outer_ring
          FROM ST_DumpRings($1)
          WHERE path[1] = 0 /* ie the outer ring */
        ),  ARRAY(/* Get all inner rings > a particular area */
        SELECT ST_ExteriorRing(geom) AS inner_rings
          FROM ST_DumpRings($1)
          WHERE path[1] > 0 /* ie not the outer ring */
            AND ST_Area(geom) >= $2
        ) ) AS final_geom
$BODY$
  LANGUAGE 'sql' IMMUTABLE;
```

### 5.2 Usar la función para eliminar áreas pequeñas

```sql
-- drop table ppr_biomes_dump_filtered ;
CREATE TABLe ppr_biomes_dump_filtered AS
SELECT id, path[1], filter_rings(geom, 1e4) AS geom 
  FROM ppr_biomes_dump
 WHERE st_area(geom) > 1e4;
-- SELECT 431296
```

Para hechar un vistazo:

```sql
SELECT id, path, st_npoints(geom), st_area(geom) 
  FROM ppr_biomes_dump_filtered
 ORDER BY st_area(geom) -- Para ver el área mínima de los poly
 LIMIT 10;
```

Crear índice en la tabla, creando la columna gid

```sql
ALTER TABLE ppr_biomes_dump_filtered ADD COLUMN gid SERIAL PRIMARY KEY;
CREATE INDEX sidx_ppr_biomes_dump_filtered_geom 
    ON ppr_biomes_dump_filtered USING GIST (geom);
```

## 6. Buffer

Este es un truco para solucionar problemas de polígonos interceptándose a sí
mismos.

```sql
EXPLAIN ANALYZE UPDATE ppr_biomes_dump_filtered 
  SET geom = ST_Buffer(geom, 0) \g salida.txt
-- 3'42"
```

El problema de este truco es que genera geometrías MultiPolygon (96 de 431296).
Se puede verificar si hay o no con este comando:

```sql
SELECT COUNT(*), st_GeometryType(geom) 
  FROM ppr_biomes_dump_filtered 
 GROUP BY st_GeometryType(geom);
```

Debido a esto es que se ejecutan los comandos de la siguiente sección...

## 7. Multi -> Single Polygon parte 2

Este paso hace 2 cosas:

   1. Rompe los ST_MultiPolygon en pedazos simples, dejando objetos de clase
      ST_Polygon solamente.
   2. Elimina polígonos de área menor a 1 hectárea.

Tabla chica, con sólo los MultiPolygon, convertidos en "single":

```sql
CREATE TABLE ppr_biomes_dump2 AS
SELECT id, path AS path0, (ST_Dump(geom)).*, gid -- gid = nextval?
  FROM ppr_biomes_dump_filtered
 WHERE ST_GeometryType(geom) = 'ST_MultiPolygon';
```
    
Usar los `gid` en la tabla chica, para sacar los Multi de la tabla original:

```sql
DELETE FROM ppr_biomes_dump_filtered 
 WHERE gid IN (SELECT gid FROM ppr_biomes_dump2)
    OR ST_Area(geom) < 1e4;
```
    
De la tabla chica, sacamos los chicos (menores a 1 hectárea):

```sql
DELETE FROM ppr_biomes_dump2
 WHERE ST_Area(geom) < 1e4;
```
    
Metemos los polígonos de la tabla chica en la original. En dos pasos, ya que hay
que poner primero el polígono principal (`path[1] = 1`) y luego los secundarios
(`path[1] <> 1`):

```sql
INSERT INTO ppr_biomes_dump_filtered
  SELECT id, path0 AS path, geom, gid
    FROM ppr_biomes_dump2
   WHERE path[1] = 1;

INSERT INTO ppr_biomes_dump_filtered
SELECT id, path0 as path, geom, 
       nextval('ppr_biomes_dump_filtered_gid_seq') AS gid
  FROM ppr_biomes_dump2
 WHERE path[1] <> 1;
```

Checkeos de que esté todo bien...

1. No hay más MultiPolygons:

```sql
SELECT count(*), st_GeometryType(geom) 
  FROM ppr_biomes_dump_filtered 
 GROUP BY st_GeometryType(geom);
```

2. Tampoco hay áreas menores a 1 há:

```sql
SELECT min(ST_Area(geom)) FROM ppr_biomes_dump_filtered;
```

## 8. Crear bioma_ref

La tabla `bioma_ref` será usada sobre para vincular los id de los biomas con los
códigos de los mismos (columna `cod_sitfin`). Es parte del producto final para
VS, pero también necesaria para crear `bfilt_snap`:

```sql
DROP TABLE bioma_ref;
CREATE TABLE bioma_ref AS 
SELECT row_number() OVER(ORDER BY code) AS id, code 
  FROM (SELECT DISTINCT cod_sitfin AS code FROM ppr_biomes_bak);
```

## 9. Tabla bfilt_snap

Es capa vectorial. Toma los polígonos de `ppr_biomes_dump_filtered`. Agrega la
columna id de la tabla `ppr_biomes_bak`. Tiene repetidos ya que los
multipolygon fueron dumpeados ("multi to single")

Además usa la función `ST_SnapToGrid`, para reducir los errores...

También toma `cod_sitfin` de la columna "code" de la tabla `bioma_ref` (ver más
arriba).

```sql
CREATE TABLE bfilt_snap AS
SELECT bf.gid, bf.id, bf.path, 
       k.cod_sitfin, s.id AS bioma_id, 
       ST_SnapToGrid(bf.geom, 0.05) AS geom
  FROM ppr_biomes_dump_filtered bf
  LEFT JOIN ppr_biomes_bak k ON bf.id = k.id
  LEFT JOIN bioma_ref s      ON k.cod_sitfin = s.code;
-- SELECT 431289

ALTER TABLE bfilt_snap ADD PRIMARY KEY (gid);
```

Comprobar que está todo en orden:

```sql
SELECT bf.gid, bf.id, bf.path, b.id, b.cod_sitfin, st.id AS biome_code 
  FROM bfilt_snap AS bf 
  LEFT JOIN ppr_biomes_bak b ON bf.id = b.id
  LEFT JOIN bioma_ref st ON b.cod_sitfin = st.code;
```

Cambié los tamaños de las columnas, no me acuerdo por qué (acá tengo dudas de en
qué momento lo hice...).

```sql
alter table bfilt_snap add column cod_sitfin character varying(50);
alter table bfilt_snap add column bioma_id bigint;
```

Límites en coordenadas del mapa `bfilt_snap`:
xMin,yMin 353569.38,6125210.00 : xMax,yMax 859065.56,6674062.00

- - -

# Arreglos usando GRASS (y QGIS)

En esta etapa vamos a exportar la capa vectorial de biomas en forma de raster
(GeoTIFF), la cual importaremos en un *location* de GRASS (7.0). Una vez dentro
de GRASS se rellenarán los "huecos" que se generaron en los pasos de la etapa
anterior (específicamente, el paso 5.2).

## 1. Convertir bfilt_snap en raster

Cargar capa `bfilt_snap` en QGIS, guardar como shape
(`bfilt_snap.sh`) y luego exportar a raster 10 m de resolución, usando cat de
ambiente como columna para los valores.

```bash
gdal_rasterize -a id -tr 10.0 10.0 -ot Int32 -l bfilt_snap \
  /home/jmb/BioUy/SIG/Shape/bfilt_snap/bfilt_snap.shp \
  /home/jmb/BioUy/SIG/Raster/bfilt_rast.tiff
```

## 2. Preparar GRASS

Instalé GRASS 7.0 para hacer parte del proceso. Para crear un location + mapset,
se pueden correr estos comandos en la terminal:

```bash
User=$(whoami) # jmb
# Crear nueva location con el código EPSG (WGS84 + UTM21S: 32721):
grass70 -c epsg:32721 /home/$User/grassdata/BioUy
grass70 -c /home/$User/grassdata/BioUy/$User
```

## 2. Importar a GRASS

Con el GRASS abierto en la location BioUy y mapset jmb, correr (en la terminal):

```bash
# (Sat Apr 8 23:37:59 2017)

r.in.gdal input=/home/jmb/BioUy/SIG/Raster/bfilt_rast.tiff\
 output=bfilt_rast -o 

# WARNING: Over-riding projection check
# Proceeding with import of 1 raster bands...
# Importing raster map <bfilt_rast>...

# (Sat Apr  8 23:42:42 2017) Command finished (4 min 42 sec)
```

Región de cálculos ajustada al raster en cuestión:

```bash
g.region raster=bfilt_rast -p
g.region save=region_x_defecto # Para futuro uso
```

Seleccionar areas mayores a 200 mil hás: es decir, todo lo que rodea al mapa de
Uruguay. Esto lo usaré después para recortar el resultado de `r.grow.distance`

```bash
r.reclass.area --overwrite input=bfilt_rast@jmb output=bfilt_bigarea\
  value=200000 mode=greater
r.report map=bfilt_bigarea@jmb units=h
r.null map=bfilt_bigarea@jmb null=1
r.null map=bfilt_bigarea@jmb setnull=0
r.mask raster=bfilt_bigarea@jmb 
```

En caso de ser necesario:

```bash
r.mask -r ## Elimina la máscara
```

Cambiar valor de los pixeles:

```bash
r.null map=bfilt_rast@jmb setnull=0

r.grow.distance --overwrite input="bfilt_rast@jmb" \
  distance="bfilt_rast_dist" value="bfilt_rast_val" metric="euclidean"
```

## 3. Reclasificación: 

la tabla se obtiene con una consulta sql (desde el psql):

```sql
SELECT DISTINCT id || ' = ' || biome_id || ' ' || cod_sitfin 
  FROM (SELECT DISTINCT id, biome_id, cod_sitfin 
          FROM bfilt_snap 
         ORDER BY id) AS o \g tabla_reclass.txt
```

El resultado es el archivo `tabla_reclass`, que se usa en el siguiente comando
de grass:

```bash
head -n -2 /home/jmb/BioUy/tabla_reclass.txt | tail -n +3 >\
  /home/jmb/BioUy/tr.txt

r.reclass --overwrite input=bfilt_rast_val@jmb output=bfilt_rast_reclass \
  rules=/home/jmb/BioUy/tr.txt
```

Que se visualice mejor:

```bash
r.colors -e map=bfilt_rast_reclass@jmb color=bgyr
```

## 4. Padrones a raster

Exportar a raster el shape de padrones (`gdal_rasterize`... igual que antes).

```bash
gdal_rasterize -a id -tr 10.0 10.0 -ot Int32 -l PaisRural \
  /home/jmb/BioUy/SIG/Shape/paisrural/PaisRural.shp \
  /home/jmb/BioUy/SIG/Raster/PaisRural.tiff
```

Importar dicho raster a GRASS:

```bash
r.in.gdal input=/home/jmb/BioUy/SIG/Raster/PaisRural.tiff output=PaisRural \
  --overwrite -o

# Over-riding projection check
# Proceeding with import of 1 raster bands...
# Importing raster map <padrones>...
# Successfully finished
```

Debido a que usé la opción `-ot Int32` al convertir el Shape en GeoTIFF (con
`gdal_rasterize`), ahora el raster PaisRural en GRASS es CELL (números enteros,
en lugar de double precision, DCELL).

## 5. Corregir el problema del padrón 0

Ocurre que en donde no hay datos (ej: cauces de ríos, rutas, etc),
`gdal_rasterize` asigna el valor 0. Esto es un problema, porque también hay un
padrón que tiene id = 0. Para solucionarlo, la estrategia es hacer un mapa chico
en donde está dicho padrón: en este mapita sólo aparece el padrón 0, el resto es
"no data" (el mapa chico se llama *padron_arreglao*).

Luego le saco todos los píxeles con valor 0 al mapa original (PaisRural) y los
convierto en NULL. Esto elimina también el padrón 0, pero no importa, porque
luego combino los mapas *PaisRural* y *padron_arreglao*, de forma que al final,
lo único que tiene valor 0 en el raster resultante, es el padrón 0.

### 5.1 Mapa *padron_arreglao*

```bash
g.region n=6167861.71531 s=6165363.81502 e=626792.772268 w=622912.700483
g.region save=padron_cero
```

El siguiente comando hace una copia del mapa, en la nueva region (pequeña), en
la que los valores > 0 se convierten en NULL. Al final sólo quedan los píxeles
con valor 0:

```bash
r.mapcalc expression='padron_arreglao = if(PaisRural@jmb, null())' --overwrite
```

### 5.2 Pasar a NULL todos los 0 del PaisRural

```bash
g.region region=region_x_defecto@jmb

r.null map=PaisRural@jmb setnull=0
```

### 5.3 Emparchar los dos rasters

La función `r.patch` junta dos rasters de la siguiente manera: si en alguno de
los dos mapas hay NULL, entonces se llena con el valor del mapa que no tiene
NULL. En caso de que en el pixel el valor es NULL para todos los mapas, queda
NULL.

```bash
r.patch --overwrite input=PaisRural@jmb,padron_arreglao@jmb \
  output=PaisRural_fix
```

## 6. Cartas SGM

La capa original con las cartas es `utm_grid.shp`. Ese Shape fue modificado para
que incluya los nombres de las cartas (ie: Vizcaíno, Punta Muniz, etc), y además
la columna con número único es `id`. Se guardó como `Cartas_SGM.shp`, en EPSG
4326 (WGS 84), pero también se hizo una copia en proyección WGS84, UTM 21S
(EPSG:32721).

La tabla asociada a esta capa tiene las columnas `id`, `carta` y `nombre`. Para
prescindir de la columna con las geometrías, en la base PostgreSQL se creó una
copia sin esa información, a la que llamé `sgm_ref` (se usará más adelante).

```bash
v.in.ogr input=/home/jmb/BioUy/SIG/Shape/Cartas_SGM_utm21/Cartas_SGM_utm21.shp\
  layer=Cartas_SGM_utm21 output=Cartas_SGM_utm21 --overwrite
```

En caso de las cartas SGM, convertí a raster también, pero esta vez con GRASS,
ya que no es una capa tan complicada.

```bash
v.to.rast input=Cartas_SGM_utm21@jmb output=Cartas_SGM_utm21 use=attr\
 attribute_column=id label_column=carta --overwrite 
```

- - -

# Intercepciones entre capas

Aquí simplemente se hacen cálculos de las áreas de intersección entre la capa de
padrones rurales y las otras dos capas importadas (ambientes, o
`bfilt_rast_reclass` y cartas SGM, o `Cartas_SGM_utm21`). El resultado son dos
tablas guardadas en archivos csv. Ej: sabremos que dentro el padrón rural X 
ocurren los ambientes Y1, Y2, Y3 ocurren, además de qué área ocupan. En la tabla
resultante se verá algo así:

 Padrón   Ambiente   Area (m^2^)
-------- ---------- -------------
    X        Y1          233
    X        Y2         1422
    X        Y3          601

### Padrones x Ambientes:

```bash
r.stats -a -n --overwrite input=PaisRural_fix@jmb,bfilt_rast_reclass@jmb \
  output=/home/jmb/BioUy/padrones_x_ambientes.csv separator=comma
```

### Padrones x Cartas SGM:

```bash
r.stats -a -n --overwrite input=PaisRural_fix@jmb,Cartas_SGM_utm21@jmb \
  output=/home/jmb/BioUy/padrones_x_sgm.csv separator=comma
```
- - -

# Importar resultados a PostgreSQL

El resultado de esta etapa será tener las tablas:

- `padron_bioma`
- `padron_sgm`


## 1. Padrones x Ambientes

Hay que hacer una tabla temporal en donde traer todos los valores del CSV creado
anteriormente:

```sql
DROP TABLE padbio_import;
CREATE TABLE padbio_import (
  padron_id integer,
  bioma_id smallint,
  area_mc numeric(12,3)
);
    
COPY padbio_import FROM '/home/jmb/BioUy/padrones_x_ambientes.csv' DELIMITER ',' CSV;
-- COPY 708835 <- Antes de arreglar el problema de padrones repetidos
--                (padrones_int)
-- COPY 710465 <- Lógicamente, ahora hay más combinaciones padrón/ambiente
```

El siguiente código es útil para chequear que estén bien los datos:

```sql
SELECT
 padron_id, bioma_id, area_mc, pr.id, 
 pr.padron, pr.depto, ppr.id, ppr.code AS biome
  FROM padbio_import pi 
  JOIN padron_ref pr ON pi.padron_id = pr.id 
  JOIN bioma_ref ppr ON pi.bioma_id = ppr.id 
 WHERE pi.padron_id = 215666;
```

Ahora sí, hacemos la tabla `padron_bioma` definitiva:

```sql
DROP TABLE padron_bioma; -- Si estamos seguros...
    
CREATE SEQUENCE padron_bioma_id_seq START 1;
ALTER  SEQUENCE padron_bioma_id_seq RESTART WITH 1;

CREATE TABLE padron_bioma AS
SELECT
  pi.padron_id,
  pi.bioma_id,
  pi.area_mc / 1e4 AS area_has, -- Importante: el área está en metros cuad.
  nextval('padron_bioma_id_seq') AS id
  FROM padbio_import pi;
    
ALTER TABLE padron_bioma ALTER COLUMN area_has TYPE numeric(8,3);
    
ALTER TABLE public.padron_bioma
  ADD CONSTRAINT padbio_pkey PRIMARY KEY (id);
```
    
## 2. Padrones x Carta SGM  

Repitiendo los pasos del punto anterior, importamos la segunda tabla:  

    
```sql
DROP TABLE padsgm_import;
CREATE TABLE padsgm_import (
  padron_id integer,
  sgm_id smallint,
  area_mc numeric(12,3)
);
    
COPY padsgm_import FROM '/home/jmb/BioUy/padrones_x_sgm.csv' DELIMITER ',' CSV;
-- COPY 265857
-- COPY 266226 <- Lo mismo que antes..
```
    
Un par de líneas para verificar que no haya problemas:
    
```sql
SELECT padron_id, count(*) 
  FROM padsgm_import 
 GROUP BY padron_id HAVING count(*) > 1;

SELECT * FROM padsgm_import WHERE padron_id IN (
 220779, 84487, 52869, 37400, 32922, 55592, 181769,
 181283, 69586, 45553, 180356, 64267, 174600, 65066,
 76660, 44193, 57774, 28873, 26637, 121751, 87011,
 125536, 68154, 15775, 240048, 183604, 246281, 128697
 );
```

Ahora sí, la tabla `padron_sgm` definitiva:

```sql
DROP TABLE padron_sgm; -- Si estamos seguros...

CREATE SEQUENCE padron_sgm_id_seq START 1;
ALTER  SEQUENCE padron_sgm_id_seq RESTART WITH 1;
    
CREATE TABLE padron_sgm AS
SELECT
  pi.padron_id,
  pi.sgm_id,
  pi.area_mc / 1e4 AS area_has,
  nextval('padron_sgm_id_seq') AS id
  FROM padsgm_import pi;

ALTER TABLE padron_sgm ALTER COLUMN area_has TYPE numeric(8,3);

ALTER TABLE public.padron_sgm
  ADD CONSTRAINT padsgm_pkey PRIMARY KEY (id);

DROP TABLE padsgm_import;
```

- - -

# Tablas de referencia en PostgreSQL

Tenemos 3 tipos de "objetos", y para cada uno corresponde una tabla de
referencia con identificador único:

1. `padron_ref`
2. `bioma_ref`
3. `sgm_ref`

Estas tablas se sumarán a las ya creadas, conformando las 5 tablas del producto
(Fig. 1):

4. `padron_bioma`
5. `padron_sgm`

## 1. Creación de las tablas `_ref`

### 1.1 Tabla bioma_ref

Ya creada, necesaria también para armar `bfilt_snap` (ver arriba).

### 1.2 Tabla padron_ref

La tabla `padron_cent` (centroides de los padrones rurales) se obtiene con QGIS
(Menú > Vector > Geometry Tools > Polygon Centroids). Esta se usará como
referencia para la interfaz (sabiendo el centroide se puede desambiguar el
padrón).

Estos primeros comandos copian el formato de `padron_cent`, eliminan varias
columnas y luego importan los datos que necesita desde la propia `padron_cent`,
para crear `padron_ref`:

```sql
CREATE TABLE padron_ref (LIKE padron_cent INCLUDING CONSTRAINTS);

ALTER TABLE padron_ref DROP geom;
ALTER TABLE padron_ref DROP areaha;
ALTER TABLE padron_ref DROP areamc;
ALTER TABLE padron_ref DROP valorreal;

INSERT INTO padron_ref (id, padron, depto, seccat, lamina, cuadricula, lat, lon)

SELECT id, padron, depto, seccat, lamina, cuadricula, lat, lon
  FROM padron_cent;
```
### 1.3

Con QGIS importé el archivo `Cartas_SGM.shp` a la base de datos. Este Shape
contiene las dimensiones de las cartas así como su código (A17, E29, etc) y su
nombre (Vizcaíno, Punta Muníz, etc). La tabla `sgm_ref` es básicamente la tabla
asociada a este Shape, eliminando solamente la columna `geom`.

Usando comandos SQL se hace un Primary Key con la columna id.

## 2. Establecer los vínculos entre tablas

Para asegurar que haya una correcta relación entre todos los
elementos, se construiran 4 *Foreign Keys* (ver Figura 1):

    1. padron_bioma (padron_id): refiere a   padron_ref (id)
    2. padron_bioma (bioma_id):  refiere a   bioma_ref (id)
    3. padron_sgm (padron_id):   refiere a   padron_ref (id)
    4. padron_sgm (sgm_id):      refiere a   sgm_ref (gid)

### 2.1 Vínculo: padron_bioma --> padron_ref

Hay que agregar algunas restricciones: un Primary Key y un Foreign Key. Este
último vinculando el id del padrón en `padron_ref` con el de `padron_bioma`:

```sql
ALTER TABLE public.padron_ref
  ADD CONSTRAINT padron_ref_pkey PRIMARY KEY (id);

ALTER TABLE public.padron_bioma
  ADD CONSTRAINT padbio_pad_fkey FOREIGN KEY (padron_id) REFERENCES 
      public.padron_ref (id)
   ON UPDATE NO ACTION ON DELETE NO ACTION;

CREATE INDEX fki_padbio_pad_fkey
    ON public.padron_bioma(padron_id);
```

### 2.2 Vínculo: padron_bioma --> bioma_ref

Lo mismo ahora, pero vinculando el id de los biomas entre las tablas
`bioma_ref` y `padron_bioma`:

```sql
ALTER TABLE public.padron_bioma
  ADD CONSTRAINT padbio_bio_fkey FOREIGN KEY (bioma_id) REFERENCES 
      public.bioma_ref (id)
   ON UPDATE NO ACTION ON DELETE NO ACTION;

CREATE INDEX fki_padbio_bio_fkey
    ON public.padron_bioma(bioma_id);

ALTER TABLE public.bioma_ref
  ADD CONSTRAINT ppr_sitfin_pkey PRIMARY KEY (id);
```

### 2.3 Vínculo: padron_sgm --> padron_ref

Las mismas consideraciones con los id de las cartas sgm. Primero, vincular
`padron_sgm` con `padron_ref` (id de los padrones):

```sql
ALTER TABLE public.padron_sgm
  ADD CONSTRAINT padsgm_pad_fkey FOREIGN KEY (padron_id) REFERENCES
      public.padron_ref (id)
   ON UPDATE NO ACTION ON DELETE NO ACTION;

CREATE INDEX fki_padsgm_pad_fkey
    ON public.padron_sgm(padron_id);
```

### 2.4 Vínculo: padron_sgm --> sgm_ref

Y luego el id de las cartas sgm, vinculando `sgm_ref` con `padron_sgm`:

```sql
ALTER TABLE public.sgm_ref
  ADD CONSTRAINT sgmref_pkey PRIMARY KEY (gid);

ALTER TABLE public.padron_sgm
  ADD CONSTRAINT padsgm_sgm_fkey FOREIGN KEY (sgm_id) REFERENCES
      public.sgm_ref (id)
   ON UPDATE NO ACTION ON DELETE NO ACTION;

CREATE INDEX fki_padsgm_sgm_fkey
    ON public.padron_sgm(sgm_id);
```

- - -

# Arreglos 19/8/2017

- BoPPLENNN-b: equivale con BoArPPLENNN-b en la BDsnap. Hay que modificar en las
  tablas a BoArPPLENNN-b

- Ba-PaPPPLTNN: equivale con BaPPPLTNN en la BDsnap. Hay que unificarlos como
  BaPPPLTNN

- BoPPPLINN: equivale con RiPPPLINN en la BDsnap. Hay que unificarlos como
  RiPPPLINN

- D: es un error del shape: hay que eliminarlo

- P: es un error del shape: hay que eliminarlo

- O: es un error del shape: hay que eliminarlo  

## bfilt_snap

```sql
UPDATE bfilt_snap SET cod_sitfin = 'BaPPPLTNN', biome_id = 15 WHERE biome_id = 10;
UPDATE bfilt_snap SET cod_sitfin = 'BoArPPLENNN-b' WHERE biome_id = 24;
UPDATE bfilt_snap SET cod_sitfin = 'RiPPPLINN', biome_id = 120 WHERE biome_id = 25;
DELETE FROM bfilt_snap WHERE biome_id IN (34, 36, 37);
```
A partir de este último cambio se puede modificar todo: el raster
`bfilt_rast.tiff` y luego todos los pasos de la creación de la tabla
`padron_bioma`. Para esto se repiten los pasos necesarios, desde la exportación
de `bfilt_snap` a Shape (hecha con QGIS) hasta obtener la tabla
`padrones_x_ambientes.csv`.

## padron_bioma

Ahora es tiempo de borrar los datos dentro de `padron_bioma` e ingresar nuevos.
Hay que reiniciar la secuencia `padron_bioma_id_seq`, para tener nuevos id.

No sé si será útil, pero pongo un valor por defecto para el id de `padron_bioma`
(el siguiente valor de la secuencia mencionada).

```sql
ALTER TABLE padron_bioma ALTER COLUMN id SET DEFAULT 
  nextval('padron_bioma_id_seq'::regclass);
```

Truncar la tabla y reiniciar la secuenca:

```sql
TRUNCATE padron_bioma;
ALTER  SEQUENCE padron_bioma_id_seq RESTART WITH 1;
```

Y, finalmente, importar los datos (con la tabla intermedia `padbio_import`):

```sql
DROP TABLE padbio_import;
CREATE TABLE padbio_import (
  padron_id integer,
  bioma_id smallint,
  area_mc numeric(12,3)
);
    
COPY padbio_import FROM '/home/jmb/BioUy/padrones_x_ambientes.csv' DELIMITER ',' CSV;

INSERT INTO padron_bioma 
  SELECT padron_id, 
         bioma_id,
         area_mc / 1e4 AS area_has,
         nextval('padron_bioma_id_seq') AS id
    FROM padbio_import 
   ORDER BY padron_id, bioma_id;
```

## bioma_ref

```sql
DELETE FROM bioma_ref WHERE id IN (10, 25);
UPDATE bioma_ref SET code = 'BoArPPLENNN-b' WHERE id = 24;
DELETE FROM bioma_ref WHERE id IN (34, 36, 37);
```
# Mapa de coberturas (Raster)

Exportarlo desde GRASS:

```bash
camino='/home/jmb/BioUy/SIG/Raster'
# (Fri Sep  1 16:58:34 2017)  
r.out.gdal -m -t --overwrite\
  input=bfilt_rast_reclass@jmb output=$camino/cobertura_ppr.tiff\
  format=GTiff type=Byte  
# Checking GDAL data type and nodata value...  
# Using GDAL data type <Byte>  
# Input raster map contains cells with NULL-value (no-data). The value 255 will
# be used to represent no-data values in the input map. You can specify a nodata
# value with the nodata option.  
# Exporting raster data to GTiff format...  
# r.out.gdal complete. File </home/jmb/BioUy/SIG/Raster/cobertura_ppr.tiff>
# created.
# (Fri Sep  1 17:03:17 2017) Command finished (4 min 43 sec)  
```

En QGIS:

Los siguientes pasos no son estrictamente necesarios. Al cargar la capa raster
se pueden consultar los valores de cobertura con la herramienta identify, pero
sólo nos va a dar el valor numérico del id de cada bioma (equivalente al
`bioma_id` de la tabla `bioma_ref`). Se pueden agregar etiquetas, aunque no son
terriblemente útiles. Para eso hay que crear un archivo de mapa de colores (o
tabla de colores), con los siguientes pasos:  

- Cargar la capa raster 'cobertura_ppr.tiff'
- Abrir propiedades del raster, pestaña Style
- Render type: Singleband pseudocolor
- Apretar botón de "Load color band from file" 
  (3ro a la derecha del botón "Classify")
- Guardar tabla de colores con el botón "Export color map to file" (último a la
  derecha de "classify") como "tabla.txt"

Luego en la terminal se recortan las primeras dos lineas del archivo:


```bash
tail -n +3 tabla.txt > /tmp/colortable.csv
```

Ahora hay que preparar la base PostgreSQL (con una tabla nueva: `colores`) e importar los datos:

```sql
--DROP TABLE colores;
CREATE TABLE colores (
  bioma_id smallint,
  alpha smallint,
  R smallint,
  G smallint,
  B smallint,
  label character varying(50)
);

COPY colores FROM '/tmp/colortable.csv' DELIMITER ',' CSV;
```

La tabla que necesitamos debe tener las etiquetas correctas en la última
columna, así que hacemos un `LEFT JOIN` para crear una tabla nueva:

```sql
CREATE TABLE color_table AS
SELECT c.bioma_id, c.alpha, c.r, c.g, c.b, 
  CASE WHEN r.code
    IS NULL THEN to_char(c.bioma_id, '999')  
  ELSE r.code END AS label 
  FROM colores c LEFT JOIN bioma_ref r ON c.bioma_id = r.id;

DROP TABLE colores;
```

Finalmente luego de creada la tabla `color_table` en la base, la exportamos como
CSV:

```sql
\COPY color_table TO '/tmp/color_table.csv' DELIMITER ',' CSV;
```

Volviendo a la terminal, se pega el encabezado del archivo `tabla.txt` a la
tabla exportada en .csv desde la base de datos:

```bash
head tabla.txt -n 2 | cat - /tmp/color_table.csv | sed "s/\s//g"\
  > /home/jmb/BioUy/SIG/Raster/color_table.txt
```

Ahora, al agregar la capa en QGIS:

- Abrir propiedades del raster, pestaña Style
- Render type: Singleband pseudocolor
- Botón "Load color map from file", elegir 
  `/home/jmb/BioUy/SIG/Raster/color_table.txt`

Listo!


