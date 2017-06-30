# Resumen

En este texto se describe el proceso de creación de las tablas que vinculan
Padrones Rurales con Ambientes y con Cartas SGM. Decidí meter el código todo
junto en este archivo, en vez de tener varios scripts separados, porque así se
conforma un tutorial. En el futuro tal vez sea mejor volver a muchos archivos
individuales.

De todas formas tener todo en un único texto ayuda a visualizar el hilo
conductor.

Nótese que acá hay código de SQL, GRASS y Bash, como mínimo.

## Sobre los archivos en la carpeta Clean:

`Voronoi.sql`: intento fallido de hacer una función con PostGIS para crear un
diagrama de Voronoi.

`voronoi_with_R.sql`: otro intento de usar diagramas de Voronoi.

`template.sql`: se usa en uno de los pasos descripto más abajo.
`master.sh`: se usa en uno de los pasos descripto más abajo.

`crear_tabla_species.sql`: no me acuerdo bien de por qué está, pero creo que es
necesaria.

`function_filter_rings.sql`: script para crear una función de PostgreSQL (+
PostGIS). En este documento hay una copia de dicho código

`function_filter_rings2.sql`: mismo que anterior, pero funcionaría para
MultiPolygon (aunque por algo no funciona).

`intento_importar_PaisRural.shp_a_GRASS.txt`: salida en standard output.

- - -

# Arreglos de la capa vectorial en PostgreSQL

Varios arreglos a la capa vectorial con los ambientes (`ppr_biomes`). Se asume
que dicha capa ya está importada dentro de la base.

## Respaldo de la tabla original

La tabla `ppr_biomes_bak` es un backup que hice de la capa de ambientes
(ppr_biomes). Acá se hace otra copia, para no tocar ese backup.

    --DROP TABLE ppr_biomes;
    CREATE TABLE ppr_biomes AS 
      SELECT id, geom FROM ppr_biomes_bak;
    -- SELECT 48523
    
    ALTER TABLE ppr_biomes ADD constraint pk_ppr_biomes_id PRIMARY KEY (id);
    
    CREATE INDEX sidx_ppr_biomes_geom ON ppr_biomes USING GIST (geom);

## Eliminar puntos repetidos

    UPDATE ppr_biomes SET geom = ST_RemoveRepeatedPoints(geom);
    -- Query returned successfully: 48523 rows affected, 04:03 minutes execution
    -- time.

## Simplificar geometrías

En PostgreSQL:

    update ppr_biomes set geom = ST_Simplify(geom, 1);

## Multi -> Single polygons (ST_Dump)

    create table ppr_biomes_dump as
      select id, (ST_Dump(geom)).* from ppr_biomes;
    -- SELECT 6798778

## Filtrar areas menores a una hectárea

### Crear función filter_rings en PostgreSQL

Sirve para eliminar áreas pequeñas.

Author: Simon Greener
Web Page: http://www.spatialdbadvisor.com/postgis_tips_tricks/92/filtering-rings-in-polygon-postgis/

> Notes: This version of the function does not handle MultiPolygon geometries. I
> choosed it because it performs better. I'm not sure if his latest version
> (which does handle MultiPoligon) is really worse performing even when dealing
> with single Polygons.

Tiene una modificación del original: en vez de `> $2`, cambié por `>= $2`.

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

### Usar la función para eliminar áreas pequeñas

    -- drop table ppr_biomes_dump_filtered ;
    create table ppr_biomes_dump_filtered as
    select id, path[1], filter_rings(geom, 1e4) as geom 
      from ppr_biomes_dump
    where st_area(geom) > 1e4;

    -- SELECT 431296

Para hechar un vistazo:

    select id, path, st_npoints(geom), st_area(geom) 
      from ppr_biomes_dump_filtered
     order by st_area(geom) -- Para ver el área mínima de los poly
      limit 10;

Crear índice en la tabla, creando la columna gid

    alter table ppr_biomes_dump_filtered add column gid serial primary key;
    CREATE INDEX sidx_ppr_biomes_dump_filtered_geom ON 
      ppr_biomes_dump_filtered USING GIST (geom);

## Buffer

Este es un truco para solucionar problemas de polígonos interceptándose a sí
mismos.

    explain analyze update ppr_biomes_dump_filtered 
      set geom = ST_Buffer(geom, 0) \g salida.txt
    -- 3'42"

El problema de este truco es que genera geometrías MultiPolygon (96 de 431296).
Se puede verificar si hay o no con este comando:

    select count(*), st_GeometryType(geom) 
      from ppr_biomes_dump_filtered 
     group by st_GeometryType(geom);

Debido a esto es que se ejecutan los comandos de la siguiente sección...

## Multi -> Single Polygon parte 2

Este paso hace 2 cosas:

   1. Rompe los ST_MultiPolygon en pedazos simples, dejando objetos de clase
      ST_Polygon solamente.
   2. Elimina polígonos de área menor a 1 hectárea.

Tabla chica, con sólo los MultiPolygon, convertidos en "single":

    create table ppr_biomes_dump2 as
      select id, path as path0, (ST_Dump(geom)).*, gid -- gid = nextval?
        from ppr_biomes_dump_filtered
       where ST_GeometryType(geom) = 'ST_MultiPolygon';
    
Usar los `gid` en la tabla chica, para sacar los Multi de la tabla original:

    delete from ppr_biomes_dump_filtered 
          where gid in (select gid from ppr_biomes_dump2)
             or ST_Area(geom) < 1e4;
    
De la tabla chica, sacamos los chicos (menores a 1 hectárea):

    delete from ppr_biomes_dump2
          where ST_Area(geom) < 1e4;
    
Metemos los polígonos de la tabla chica en la original. En dos pasos, ya que hay
que poner primero el polígono principal (`path[1] = 1`) y luego los secundarios
(`path[1] <> 1`):

    insert into ppr_biomes_dump_filtered
      select id, path0 as path, geom, gid
        from ppr_biomes_dump2
       where path[1] = 1;
    
    insert into ppr_biomes_dump_filtered
      select id, path0 as path, geom, 
             nextval('ppr_biomes_dump_filtered_gid_seq') as gid
        from ppr_biomes_dump2
       where path[1] <> 1;

Checkeos de que esté todo bien...

1. No hay más MultiPolygons:

    select count(*), st_GeometryType(geom) 
      from ppr_biomes_dump_filtered 
     group by st_GeometryType(geom);

2. Tampoco hay áreas menores a 1 há:

    select min(ST_Area(geom)) from ppr_biomes_dump_filtered;

## Tabla bfilt_snap

Es capa vectorial. Toma los polígonos de `ppr_biomes_dump_filtered`. Agrega la
columna id de la tabla `ppr_biomes_bak`. Tiene repetidos ya que los
multipolygon fueron dumpeados ("multi to single")

Además usa la función `ST_SnapToGrid`, para reducir los errores...

También toma `cod_sitfin` de `ppr_sitfin`, recién creada.

    create table bfilt_snap as
    select bf.gid, bf.id, bf.path, 
           k.cod_sitfin, s.id as biome_id, 
           ST_SnapToGrid(bf.geom, 0.05) as geom
      from ppr_biomes_dump_filtered bf
      left join ppr_biomes_bak k on bf.id = k.id
      left join ppr_sitfin s     on k.cod_sitfin = s.code;
    -- SELECT 431289

    ALTER TABLE bfilt_snap add PRIMARY KEY (gid);

Comprobar que está todo en orden:

    select bf.gid, bf.id, bf.path, b.id, b.cod_sitfin, st.id as biome_code 
      from bfilt_snap as bf 
      left join ppr_biomes_bak b on bf.id = b.id
      left join ppr_sitfin st on b.cod_sitfin = st.code;

Cambié los tamaños de las columnas, no me acuerdo por qué (acá tengo dudas de en
qué momento lo hice...).

    alter table bfilt_snap add column cod_sitfin character varying(50);
    alter table bfilt_snap add column biome_id bigint;

Límites en coordenadas del mapa `bfilt_snap`:
xMin,yMin 353569.38,6125210.00 : xMax,yMax 859065.56,6674062.00

- - -

# Arreglos usando GRASS (y QGIS)

## Convertir bfilt_snap en raster

Cargar capa `bfilt_snap` en QGIS, guardar como shape
(`bfilt_snap.sh`) y luego exportar a raster 10 m de resolución, usando cat de
ambiente como columna para los valores.

    gdal_rasterize -a id -tr 10.0 10.0 -l bfilt_snap \
      /home/jmb/BioUy/SIG/Shape/bfilt_snap/bfilt_snap.shp \
      /home/jmb/BioUy/SIG/Raster/bfilt_rast.tiff

Son 22 GB!! Lo borré más tarde.

## Preparar GRASS

Instalé GRASS 7.0 para hacer parte del proceso. Para crear un location + mapset,
se pueden correr estos comandos en la terminal:

    User=$(whoami) # jmb
    # Crear nueva location con el código EPSG (WGS84 + UTM21S: 32721):
    grass70 -c epsg:32721 /home/$User/grassdata/BioUy
    grass70 -c /home/$User/grassdata/BioUy/$User

## Importar a GRASS

Con el GRASS abierto en la location BioUy y mapset jmb, correr (en la terminal):

    # (Sat Apr 8 23:37:59 2017)

    r.in.gdal input=/home/jmb/BioUy/SIG/Raster/bfilt_rast.tiff\
     output=bfilt_rast -o 

    # WARNING: Over-riding projection check
    # Proceeding with import of 1 raster bands...
    # Importing raster map <bfilt_rast>...

    # (Sat Apr  8 23:42:42 2017) Command finished (4 min 42 sec)

Región de cálculos ajustada al raster en cuestión:

    g.region raster=bfilt_rast -p

Seleccionar areas mayores a 200 mil hás: es decir, todo lo que rodea al mapa de
Uruguay. Esto lo usaré después para recortar el resultado de `r.grow.distance`

    r.reclass.area --overwrite input=bfilt_rast@jmb output=bfilt_bigarea\
      value=200000 mode=greater
    r.report map=bfilt_bigarea@jmb units=h
    r.null map=bfilt_bigarea@jmb null=1
    r.null map=bfilt_bigarea@jmb setnull=0
    r.mask raster=bfilt_bigarea@jmb 

En caso de ser neceario:

    r.mask -r ## Elimina la máscara

Cambiar valor de los pixeles:

    r.null map=bfilt_rast@jmb setnull=0

    r.grow.distance --overwrite input="bfilt_rast@jmb" \
      distance="bfilt_rast_dist" value="bfilt_rast_val" metric="euclidean"

## Reclasificación: 

la tabla se obtiene con una consulta sql (desde el psql):

    select distinct id || ' = ' || biome_id || ' ' || cod_sitfin 
      from (select distinct id, biome_id, cod_sitfin 
              from bfilt_snap 
             order by id) as o \g tabla_reclass.txt

El resultado es el archivo `tabla_reclass`, que se usa en el siguiente comando
de grass:

    r.reclass --overwrite input=bfilt_rast_val@jmb output=bfilt_rast_reclass \
      rules=/home/jmb/BioUy/tabla_reclass.txt

Que se visualice mejor:

    r.colors -e map=bfilt_rast_reclass@jmb color=bgyr

Exportar a raster el shape de padrones (`gdal_rasterize`... igual que antes).

Importar dicho raster a GRASS:

    r.in.gdal input=/home/jmb/BioUy/SIG/Raster/padrones_rast.tiff\
     output=padrones -o

    # Over-riding projection check
    # Proceeding with import of 1 raster bands...
    # Importing raster map <padrones>...
    # Successfully finished

Ahora se usa el archivo creado antes (`tabla_reclass.txt`)... En este caso, tal
ves porque usé el GUI, aparece un archivo temporal ("4829.0", ver abajo).

    # (Mon Apr 10 18:24:55 2017)

    r.recode --verbose input=padrones@jmb output=padrones_int \
      rules=/home/jmb/SIG/grassdata/BioUy/jmb/.tmp/gis-probides/4829.0

    # (Mon Apr 10 18:26:54 2017) Command finished (1 min 59 sec)

- - -

# Intercepciones entre capas ... PASO MEJORABLE?

Para cruzar los padrones con el raster de los ambientes y con el raster de las
cartas del SGM (la cual genero más abajo), convertí el raster de
padrones a un vectorial en el que cada pixel es un punto... Hay buenas chances
de que no sea la opción más óptima, pero es lo que me sirvió en el momento.

    # (Mon Apr 10 19:36:35 2017)

    r.to.vect -v --overwrite input=padrones_int@jmb \
      output=padrones_point type=point column=pad_id

    # WARNING: Vector map <padrones_point> already exists and will be overwritten
    # Extracting points...
    # ERROR: Category index is not up to date

    # (Tue Apr 11 03:57:07 2017) Command finished (161 min 32 sec)

La capa `padrones_point` pesa 49 GB !!

    # (Tue Apr 11 10:02:01 2017)                                                      

    v.in.ogr input=/home/jmb/BioUy/SIG/Shape/utm_grid2 layer=utm_grid2\
     output=utm_grid2 --overwrite encoding=utf8

    # Check if OGR layer <utm_grid2> contains polygons...
    # WARNING: Vector map <utm_grid2> already exists and will be overwritten
    # Importing 302 features (OGR layer <utm_grid2>)...

    # (continúa....)

En caso de las cartas SGM, convertí a raster también, pero esta vez con GRASS,
ya que no es una capa tan complicada.

    v.to.rast --overwrite input=utm_grid2@jmb output=utm_grid2 use=attr\
     attribute_column=gid label_column=carta


### Acá es donde cruzo varias capas:

    r.what -n -f -c --overwrite --verbose\
     map=bfilt_rast_reclass@jmb,padrones_int@jmb,utm_grid2@jmb\
     points=padrones_point@jmb output=/home/jmb/BioUy/output_r.what.csv\
     separator=comma

    # (Wed Apr 12 01:35:04 2017) Command finished (923 min 59 sec)
    # 15 horas!

- - -

# Importar resultados a PostgreSQL

## Manejar la salida de r.what

Lo primero fue sacar algunas columnas que no nos interesan:

    cut -d, -f1,2,3,7 --complement output_r.what.csv > output_r.what2.csv

Hacer un encabezado:

    echo "biome_id,biome_code,padron_id,sgm_id,sgm_code" > header.txt

Cambiar el encabezado original por el que nuevo:

    tail -n +2 output_r.what2.csv | cat header.txt - > output_r.what3.csv

Hay que detectar y arreglar errores:

    egrep "\*" output_r.what3.csv -n > errores.txt

El archivo de arriba tiene los números de línea, por lo que se puede armar un
`sed` que modifique específicamente esos casos (cambiando un asterisco por -1):

    sed -e '52276355s/\*/-1/g' \
        -e '53738318s/\*/-1/g' \
        -e '56653927s/\*/-1/g' \
        -e '64177173s/\*/-1/g' \
        -e '597387987s/\*/-1/g' \
        -e '630807519s/\*/-1/g' \
        -e '1008961510s/\*/-1/g' \
        -e '1064967730s/\*/-1/g' \
        output_r.what3.csv > output_r.what4.csv
    
Estos comandos los escribí acá, pero no estoy seguro de haberlos ejecutado.
Serían para borrar las líneas con error en `output_r.what4.csv`

    sed -n '52276355p' output_r.what4.csv
    sed -n '53738318p' output_r.what4.csv
    sed -n '56653927p' output_r.what4.csv
    sed -n '64177173p' output_r.what4.csv
    sed -n '597387987p' output_r.wat4.csv
    sed -n '630807519p' output_r.wat4.csv
    sed -n '1008961510p' output_r.what4.csv
    sed -n '1064967730p' output_r.what4.csv

### Partirlo en pedazos

Ahora que el formato está bien, hay que partirlo en pedazos más chicos (20
partes, para ser precisos), y manejables (ver abajo en COPY):

    split -n l/20 -d -u output_r.what4.csv out_what_ --additional-suffix=.txt

### Ver el rango de valores de la capa raster:

    r.describe -r map=padrones_int@jmb
    0
    1 thru 250158
    *

El asterisco sería los NULL, creo.

Ahora en PostgreSQL, creo una tabla en donde voy a meter los valores de
output_r.what4.csv:

    CREATE TABLE output_what (
      biome_id smallint, 
      biome_code character varying(20),
      padron_id integer,
      utm_id smallint,
      utm_code character varying(3)
    );

### Por qué partirlo en 20?

El archivo entero (de 46 GB), no entra:

    COPY output_what FROM '/home/jmb/BioUy/output_r.what4.csv' DELIMITER ',' CSV HEADER;
    ERROR:  could not extend file "base/25496/600076.7": No space left on device
    HINT:  Check free disk space.
    CONTEXT:  COPY output_what, line 1001

En ese momento la base de datos estaba en el disco raíz de la máquina (archivos
del sistema operativo), que es una partición distinta a la del `~`, por esto es
que no me daba el espacio. No debería ser problema si hay suficiente espacio en
el disco en que está la base de datos.

Este es un vistazo de cómo se ve el `output_r.what4.csv`:

    biome_id, biome_code,      padron_id,  sgm_id, sgm_code
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    32,       cuerpos loticos, 0,          193,    P12
    115,      PrPSPRNNM,       101899,     280,    M15
    115,      PrPSPRNNM,       101899,     280,    M15
    115,      PrPSPRNNM,       101899,     280,    M15
    115,      PrPSPRNNM,       101899,     280,    M15
    123,      suelo desnudo,   101899,     280,    M15
    123,      suelo desnudo,   101899,     280,    M15
    123,      suelo desnudo,   101899,     280,    M15
    123,      suelo desnudo,   101899,     280,    M15
    123,      suelo desnudo,   101899,     280,    M15
    
## Pasos iterativos para importar los datos

Para resolver el problema de espacio en disco, resolví iterar un procedimiento:

1. Meter datos en `output_what` (tabla en mi base PostgreSQL)
2. Hacer un par de Group By de esos datos, y mandarlos para tablas temporales.
   Serían Group By por padrones + biomas y por padrones + sgm.
3. Las tablas temporales se agrandan con cada pedazo del `output_r.what4.csv`
   original que importo al PostgreSQL.
4. Una vez importados todos los datos, hago tablas definitivas, volviendo a
   agrupar por padrón + biome y padrón + sgm.

De nuevo, la complejidad del procedimiento no sería necesaria, en teoría, si la
base estuviera en una partición de disco lo suficientemente grande.

### 1. Importar datos crudos en output_what

    TRUNCATE output_what;
    COPY output_what FROM '/home/jmb/BioUy/out_what_00.txt' DELIMITER ',' CSV HEADER;

    COPY 94967658
         91887637
         89170614
         88029812
         87024329
         86922890
         87107413
         86696040
    (continúa...)

Estos no andaban por falta de espacio:

    CREATE INDEX owhat_pad_biomes_ix ON output_what (padron_id, biome_id);
    CREATE INDEX owhat_pad_ix ON output_what (padron_id);

### 2 Agrupar datos iniciando tablas temporales

Se crean dos tablas que van a ser el primer paso para agrupar la salida de
`output_r.what4.csv`. El agrupamiento es haciendo `count(*)` de las filas.
Sabiendo que dada fila corresponde a un pixel de 10m x 10m, el count es una
forma de llegar al área total.

Comando de Group By con padrón + bioma, crea la tabla temporal `pad_biome`:

    CREATE TABLE pad_biome AS
    SELECT padron_id, biome_id, count(*) AS n
      FROM output_what
     GROUP BY padron_id, biome_id;

    SELECT 19265
    INSERT 0 22178
             26928
             22644
             23505
    (continúa...)
 
Comando de Group By con padrón + sgm, crea la tabla temporal `pad_sgm`:

    CREATE TABLE pad_sgm AS
    SELECT padron_id, utm_id AS sgm_id, count(*) AS n
      FROM output_what
     GROUP BY padron_id, utm_id;

    SELECT 6624
    INSERT 0 7969
             9164
             8041
             8215
    (continúa...)

### 3 Agregar datos a las tablas temporales

Acá es donde se da el verdadero ciclo de importación. Primero se vacía y vuelve
a llenar la tabla `output_what`:

    TRUNCATE output_what;
    COPY output_what FROM '/home/jmb/BioUy/out_what_05.txt' DELIMITER ',' CSV;

A continuación se agregan datos a las tablas temporales, usando comandos `GROUP
BY` correspondientes:

    INSERT INTO pad_biome (padron_id, biome_id, n)
    SELECT padron_id, biome_id, count(*) AS n
      FROM output_what
     GROUP BY padron_id, biome_id;
    
    INSERT INTO  pad_sgm (padron_id, sgm_id, n)
    SELECT padron_id, utm_id AS sgm_id, count(*) AS n
      FROM output_what
     GROUP BY padron_id, utm_id;

Estos pasos, por ser engorrosos de repetir 19 veces, se pueden hacer con los
scripts:

- `template.sql`: tiene los comandos SQL para importar a PostgreSQL.
- `master.sh`: edita `template.sql` y loopea para importar todo.

### 4 Agrupar todo en tablas definitivas

Acá agrupo las entradas de las tablas temporales, `pad_biome` y `pad_sgm`, y al
mismo tiempo creo las tablas definitivas, `padron_biome` y `padron_sgm`
correspondientes:

    CREATE TABLE padron_biome AS
    SELECT padron_id, biome_id, sum(n) AS N
      FROM pad_biome
     GROUP BY padron_id, biome_id;
    /*
     SELECT COUNT(*) FROM pad_biome;
     --> 730266
     SELECT COUNT(*) FROM padron_biome;
     --> 708953
    */

Como corresponde, `padron_biome` tiene menos datos que `pad_biome`. Lo mismo
pasa con las tablas correspondientes a padrón + sgm:
    
    CREATE TABLE padron_sgm AS
    SELECT padron_id, sgm_id, sum(n) AS N
      FROM pad_sgm
     GROUP BY padron_id, sgm_id;
    /*
     SELECT COUNT(*) FROM pad_sgm;
     --> 274839
     SELECT COUNT(*) FROM padron_sgm;
     --> 266163
    */

Limpieza, si estamos muy seguro de que quedó todo bien:

    DROP TABLE pad_biome;
    DROP TABLE pad_sgm;

También modifico las tablas definitivas. La columna "n" ahora tendrá el área de
cada entrada medida en hectáreas:

    UPDATE padron_biome SET n = n / 100;
    ALTER TABLE padron_biome RENAME COLUMN n TO area_has;
    ALTER TABLE padron_biome ALTER area_has SET DATA TYPE NUMERIC(9, 3);

    UPDATE padron_sgm SET n = n / 100;
    ALTER TABLE padron_sgm RENAME COLUMN n TO area_has;
    ALTER TABLE padron_sgm ALTER area_has SET DATA TYPE NUMERIC(8, 3);

- - -

# Tablas de referencia en PostgreSQL

Son tablas que relacionan los códigos de los biomas, sgm y padrones. Se hacen
Foreign Keys para esto:

    padron_biome (padron_id) -- padron_ref (id)
    padron_biome (biome_id)  -- ppr_sitfin (id)
    padron_sgm (padron_id)   -- padron_ref (id)
    padron_sgm (sgm_id)      -- utm_grid2 (gid)

## Tabla ppr_sitfin

Será usada sobre para vincular los id de los biomas con los códigos de
los mismos (columna `cod_sitfin`):

    create table ppr_sitfin as 
    select row_number() over(order by code) as id, code 
      from (select distinct cod_sitfin as code 
      from ppr_biomes_bak) as sitfin;
    -- SELECT 124

## Tabla padron_ref

La tabla `padron_cent` (centroides de los padrones rurales) se obtiene con QGIS
(Menú > Vector > Geometry Tools > Polygon Centroids). Esta se usará como
referencia para la interfaz (sabiendo el centroide se puede desambiguar el
padrón).

Estos primeros comandos copian el formato de `padron_cent`, eliminan varias
columnas y luego importan los datos que necesita desde la propia `padron_cent`,
para crear `padron_ref`:

    CREATE TABLE padron_ref
    (LIKE padron_cent INCLUDING CONSTRAINTS);
    ALTER TABLE padron_ref DROP geom;
    ALTER TABLE padron_ref DROP areaha;
    ALTER TABLE padron_ref DROP areamc;
    ALTER TABLE padron_ref DROP valorreal;
    INSERT INTO padron_ref (id, padron, depto, seccat, lamina, cuadricula, lat, lon)
    SELECT id, padron, depto, seccat, lamina, cuadricula, lat, lon
      FROM padron_cent;

## Vínculo: padron_biome -- padron_ref

Hay que agregar algunas restricciones: un primary key y un foreign key. Este
último vinculando el id del padrón en `padron_ref` con el de `padron_biome`:

    ALTER TABLE public.padron_ref
      ADD CONSTRAINT padron_ref_pkey PRIMARY KEY (id);

    ALTER TABLE public.padron_biome
      ADD CONSTRAINT padbio_pad_fkey FOREIGN KEY (padron_id) REFERENCES public.padron_ref (id)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padbio_pad_fkey
      ON public.padron_biome(padron_id);

## Vínculo: padron_biome -- ppr_sitfin

Lo mismo ahora, pero vinculando el id de los biomas entre las tablas
`ppr_sitfin` y `padron_biome`:

    ALTER TABLE public.padron_biome
      ADD CONSTRAINT padbio_bio_fkey FOREIGN KEY (biome_id) REFERENCES public.ppr_sitfin (id)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padbio_bio_fkey
      ON public.padron_biome(biome_id);

    ALTER TABLE public.ppr_sitfin
      ADD CONSTRAINT ppr_sitfin_pkey PRIMARY KEY (id);

## Vínculo: padron_sgm -- padron_ref

Las mismas consideraciones con los id de las cartas sgm. Primero, vincular
`padron_sgm` con `padron_ref` (id de los padrones):

    ALTER TABLE public.padron_sgm
      ADD CONSTRAINT padsgm_pad_fkey FOREIGN KEY (padron_id) REFERENCES
      public.padron_ref (id)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padsgm_pad_fkey
      ON public.padron_sgm(padron_id);

Decidí eliminar aquellas entradas en los que el id del padrón figuraba como -1:

    DELETE FROM padron_sgm WHERE sgm_id = -1;

## Vínculo: padron_sgm -- utm_grid2

Y luego el id de las cartas sgm, vinculando `utm_grid2` con `padron_sgm`:

    ALTER TABLE public.utm_grid2
      ADD CONSTRAINT utm_grid2_pkey PRIMARY KEY (gid);

    ALTER TABLE public.padron_sgm
      ADD CONSTRAINT padsgm_sgm_fkey FOREIGN KEY (sgm_id) REFERENCES
      public.utm_grid2 (gid)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padsgm_sgm_fkey
      ON public.padron_sgm(sgm_id);

