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

    gdal_rasterize -a id -tr 10.0 10.0 -ot Int32 -l bfilt_snap \
      /home/jmb/BioUy/SIG/Shape/bfilt_snap/bfilt_snap.shp \
      /home/jmb/BioUy/SIG/Raster/bfilt_rast.tiff

Son 22 GB!! Lo borré más tarde.

**Nota**: esto fue la primera vez, ahora el comando lo modifiqué para que exporte
con Int32 (antes era Float64, el valor por defecto).
*Espero que este cambio no afecte a los pasos subsiguientes. No verifiqué que
funcione todo bien.*

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
    g.region save=region_x_defecto # Para futuro uso

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

## Padrones a raster

Exportar a raster el shape de padrones (`gdal_rasterize`... igual que antes).

    gdal_rasterize -a id -tr 10.0 10.0 -ot Int32 -l PaisRural \
      /home/jmb/BioUy/SIG/Shape/paisrural/PaisRural.shp \
      /home/jmb/BioUy/SIG/Raster/PaisRural.tiff


Importar dicho raster a GRASS:

    r.in.gdal input=/home/jmb/BioUy/SIG/Raster/PaisRural.tiff output=PaisRural \
      --overwrite -o

    # Over-riding projection check
    # Proceeding with import of 1 raster bands...
    # Importing raster map <padrones>...
    # Successfully finished

Debido a que usé la opción `-ot Int32` al convertir el Shape en GeoTIFF (con
`gdal_rasterize`), ahora el raster PaisRural en GRASS es CELL (números enteros,
en lugar de double precision, DCELL).

## Corregir el problema del padrón 0

Ocurre que en donde no hay datos (ej: cauces de ríos, rutas, etc),
`gdal_rasterize` asigna el valor 0. Esto es un problema, porque también hay un
padrón que tiene id = 0. Para solucionarlo, la estrategia es hacer un mapa chico
en donde está dicho padrón: en este mapita sólo aparece el padrón 0, el resto es
"no data" (el mapa chico se llama *padron_arreglao*).

Luego le saco todos los píxeles con valor 0 al mapa original (PaisRural) y los
convierto en NULL. Esto elimina también el padrón 0, pero no importa, porque
luego combino los mapas *PaisRural* y *padron_arreglao*, de forma que al final,
lo único que tiene valor 0 en el raster resultante, es el padrón 0.

### Mapa *padron_arreglao*

    g.region n=6167861.71531 s=6165363.81502 e=626792.772268 w=622912.700483
    g.region save=padron_cero

El siguiente comando hace una copia del mapa, en la nueva region (pequeña), en
la que los valores > 0 se convierten en NULL. Al final sólo quedan los píxeles
con valor 0:

    r.mapcalc expression='padron_arreglao = if(PaisRural@jmb, null())' \
      --overwrite

### Pasar a NULL todos los 0 del PaisRural

    g.region region=region_x_defecto@jmb

    r.null map=PaisRural@jmb setnull=0

### Emparchar los dos rasters

La función `r.patch` junta dos rasters de la siguiente manera: si en alguno de
los dos mapas hay NULL, entonces se llena con el valor del mapa que no tiene
NULL. En caso de que en el pixel el valor es NULL para todos los mapas, queda
NULL.

    r.patch --overwrite input=PaisRural@jmb,padron_arreglao@jmb \
      output=PaisRural_fix


## Cartas SGM

En caso de las cartas SGM, convertí a raster también, pero esta vez con GRASS,
ya que no es una capa tan complicada.

    v.to.rast --overwrite input=utm_grid2@jmb output=utm_grid2 use=attr\
     attribute_column=gid label_column=carta

- - -

# Intercepciones entre capas

Padrones x Ambientes:

    r.stats -a -n --overwrite input=PaisRural_fix@jmb,bfilt_rast_reclass@jmb \
      output=/home/jmb/BioUy/padrones_x_ambientes.csv separator=comma

Padrones x Cartas SGM:

    r.stats -a -n --overwrite input=PaisRural_fix@jmb,utm_grid2@jmb \
      output=/home/jmb/BioUy/padrones_x_sgm.csv separator=comma

- - -

# Importar resultados a PostgreSQL

## Padrones x Ambientes

Tabla temporal:
    DROP TABLE padbio_import;
    CREATE TABLE padbio_import (
      padron_id integer,
      biome_id smallint,
      area_mc numeric(12,3)
    );
    
    COPY padbio_import FROM '/home/jmb/BioUy/padrones_x_ambientes.csv' DELIMITER ',' CSV;
    -- COPY 708835 <- Antes de arreglar el problema de padrones repetidos
    --                (padrones_int)
    -- COPY 710465 <- Lógicamente, ahora hay más combinaciones padrón/ambiente

Código útil para chequear que estén bien los datos:

    SELECT
     padron_id, biome_id, area_mc, pr.id, 
     pr.padron, pr.depto, ppr.id, ppr.code AS biome
      FROM padbio_import pi 
      JOIN padron_ref pr ON pi.padron_id = pr.id 
      JOIN ppr_sitfin ppr ON pi.biome_id = ppr.id 
     WHERE pi.padron_id = 215666;
    

Ahora sí, hacemos la tabla `padron_biome` definitiva:

    DROP TABLE padron_biome; -- Si estamos seguros...
    
    CREATE SEQUENCE padron_biome_id_seq START 1;
    ALTER  SEQUENCE padron_biome_id_seq RESTART WITH 1;
    
    CREATE TABLE padron_biome AS
    SELECT
      pi.padron_id,
      pi.biome_id,
      pi.area_mc / 1e4 AS area_has, -- Importante: el área está en metros cuad.
      nextval('padron_biome_id_seq') AS id
      FROM padbio_import pi;
    
    ALTER TABLE padron_biome ALTER COLUMN area_has TYPE numeric(8,3);
    
    ALTER TABLE public.padron_biome
      ADD CONSTRAINT padbiome_pkey PRIMARY KEY (id);
    
    ALTER TABLE public.padron_biome
      ADD CONSTRAINT padbio_pad_fkey FOREIGN KEY (padron_id) REFERENCES public.padron_ref (id)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padbio_pad_fkey
      ON public.padron_biome(padron_id);
    
    ALTER TABLE public.padron_biome
      ADD CONSTRAINT padbio_bio_fkey FOREIGN KEY (biome_id) REFERENCES public.ppr_sitfin (id)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padbio_bio_fkey
      ON public.padron_biome(biome_id);
    
## Padrones x Carta SGM

Ahora la otra tabla temporal:
    
    DROP TABLE padsgm_import;
    CREATE TABLE padsgm_import (
      padron_id integer,
      sgm_id smallint,
      area_mc numeric(12,3)
    );
    
    COPY padsgm_import FROM '/home/jmb/BioUy/padrones_x_sgm.csv' DELIMITER ',' CSV;
    -- COPY 265857
    -- COPY 266226 <- Lo mismo que antes..
    
Un par de líneas para verificar que no haya problemas:
    
    SELECT padron_id, count(*) 
      FROM padsgm_import 
     GROUP BY padron_id HAVING count(*) > 1;
    
    SELECT * FROM padsgm_import WHERE padron_id IN (
     220779, 84487, 52869, 37400, 32922, 55592, 181769,
     181283, 69586, 45553, 180356, 64267, 174600, 65066,
     76660, 44193, 57774, 28873, 26637, 121751, 87011,
     125536, 68154, 15775, 240048, 183604, 246281, 128697
     );
    

Ahora sí, la tabla `padron_sgm` definitiva:

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
    
    ALTER TABLE public.padron_sgm
      ADD CONSTRAINT padsgm_pad_fkey FOREIGN KEY (padron_id) REFERENCES public.padron_ref (id)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padsgm_pad_fkey
      ON public.padron_sgm(padron_id);
    
    ALTER TABLE public.padron_sgm
      ADD CONSTRAINT padsgm_sgm_fkey FOREIGN KEY (sgm_id) REFERENCES
      public.utm_grid2 (gid)
       ON UPDATE NO ACTION ON DELETE NO ACTION;
    CREATE INDEX fki_padsgm_sgm_fkey
      ON public.padron_sgm(sgm_id);
    
    DROP TABLE padsgm_import;

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


## Nota al final:

Para hacer una distribución de una especie, se puede usar mapcalc para

Estos son los datos para el Coendú (según la página del SNAP):

AMBIENTES:
PaSSLRNHA, BoOMMMNNA, BoPSLENHA, RiPPPLTNN, BoOMLRNNM, BoOSLRNHA, BoPMMMNNA,
BoQ, BoSSLENHA, BoSSLRNHA, BoPSLRNHA, BoOSLENHA, RiPPPLINN, BoPMLRNNM, PaSMLRNNM

CARTAS SGM:
A17, B16, B17, B18, C13, C14, C15, C16, C17, C18, D12, D13, D14, D15, D16, D17,
D18, E10, E11, E12, E13, E14, E15, E16, E17, E18, F10, F11, F12, F13, F14, F15,
F16, F17, F18, F9, G10, G11, G12, G13, G14, G15, G16, G17, G18, G8, G9, H10,
H11, H12, H13, H14, H15, H16, H17, H18, H7, H8, H9, J10, J11, J12, J13, J14,
J15, J16, J17, J6, J7, J8, J9, K10, K11, K12, K13, K14, K15, K16, K4, K5, K6,
K7, K8, K9, L10, L11, L12, L13, L14, L15, L3, L4, L5, L6, L7, L8, L9, M10, M11,
M12, M13, M14, M15, M3, M4, M5, M6, M7, M8, M9, N10, N11, N12, N13, N14, N15,
N3, N4, N5, N6, N7, N8, N9, O13, O14, O15, O27, O4, O5, O6, O7, O8

    SELECT 'bfilt_reclass == ' || id || ' ||' from ppr_sitfin 
     WHERE code IN (
       'PaSSLRNHA', 'BoOMMMNNA', 'BoPSLENHA', 'RiPPPLTNN', 'BoOMLRNNM',
       'BoOSLRNHA', 'BoPMMMNNA', 'BoQ', 'BoSSLENHA', 'BoSSLRNHA', 'BoPSLRNHA',
       'BoOSLENHA', 'RiPPPLINN', 'BoPMLRNNM', 'PaSMLRNNM'
       )
     ORDER BY id;

    SELECT 'utm_grid2 == ' || gid || ' ||' from utm_grid2 
     WHERE carta IN (
       'A17', 'B16', 'B17', 'B18', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'D12',
       'D13', 'D14', 'D15', 'D16', 'D17', 'D18', 'E10', 'E11', 'E12', 'E13', 'E14',
       'E15', 'E16', 'E17', 'E18', 'F10', 'F11', 'F12', 'F13', 'F14', 'F15', 'F16',
       'F17', 'F18', 'F9', 'G10', 'G11', 'G12', 'G13', 'G14', 'G15', 'G16', 'G17',
       'G18', 'G8', 'G9', 'H10', 'H11', 'H12', 'H13', 'H14', 'H15', 'H16', 'H17',
       'H18', 'H7', 'H8', 'H9', 'J10', 'J11', 'J12', 'J13', 'J14', 'J15', 'J16',
       'J17', 'J6', 'J7', 'J8', 'J9', 'K10', 'K11', 'K12', 'K13', 'K14', 'K15',
       'K16', 'K4', 'K5', 'K6', 'K7', 'K8', 'K9', 'L10', 'L11', 'L12', 'L13', 'L14',
       'L15', 'L3', 'L4', 'L5', 'L6', 'L7', 'L8', 'L9', 'M10', 'M11', 'M12', 'M13',
       'M14', 'M15', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'N10', 'N11', 'N12',
       'N13', 'N14', 'N15', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'O13', 'O14',
       'O15', 'O27', 'O4', 'O5', 'O6', 'O7', 'O'
       )
     ORDER BY gid;

La idea era tirar esos resultados en el r.mapcalc de GRASS. Hice una prueba,
pero parecía ir demasiado lento, así que no seguí. De todas formas, esto tiene
el problema de que corta los límites con las cartas, en vez de abarcar todos los
parches de ambientes adecuados que tocan las cartas en algún punto.
