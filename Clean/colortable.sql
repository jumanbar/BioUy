/* En QGIS:
- Cargar la capa raster 'cobertura_ppr.tiff'
- Abrir propiedades del raster, pestaña Style
- Render type: Singleband pseudocolor
- Apretar botón de "Load color band from file" 
  (3ro a la derecha del botón "Classify")
- Guardar tabla de colores con el botón "Export color map to file" (último a la
  derecha de "classify") como "tabla.txt"
*/

--DROP TABLE colores;
CREATE TABLE colores (
  bioma_id smallint,
  alpha smallint,
  R smallint,
  G smallint,
  B smallint,
  label character varying(50)
);

/* BASH:
tail -n +3 tabla.txt > /tmp/colortable.csv
*/
    
COPY colores FROM '/tmp/colortable.csv' DELIMITER ',' CSV;

CREATE TABLE color_table AS
SELECT c.bioma_id, c.alpha, c.r, c.g, c.b, 
  CASE WHEN r.code
    IS NULL THEN to_char(c.bioma_id, '999')  
  ELSE r.code END AS label 
  FROM colores c LEFT JOIN bioma_ref r ON c.bioma_id = r.id;

\COPY color_table TO '/tmp/color_table.csv' DELIMITER ',' CSV;
/*
BASH:
head tabla.txt -n 2 | cat - /tmp/color_table.csv | sed "s/\s//g"\
  > /home/jmb/BioUy/SIG/Raster/color_table.txt
*/

/* Ahora, al agregar la capa en QGIS:
- Abrir propiedades del raster, pestaña Style
- Render type: Singleband pseudocolor
- Botón "Load color map from file", elegir 
  /home/jmb/BioUy/SIG/Raster/color_table.txt
- Listo!
*/

