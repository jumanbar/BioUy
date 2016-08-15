
/*
  QGIS: Intersect PPR + SGR => int_map
    AUTOID
    CARTA
    COD_SITTOT -- Ambiente
  sgr_spp -- Tabla con las cartas sgr y las especies allí presentes
    CARTA
    ESPECIE
    PRESENCIA
  spp_amb
    ESPECIE
    AMBIENTE
    PRESENCIA
*/
create tabla_consultas as
select * from 
  int_map i join 
  (select * from sgr_spp ss, join spp_amb sa 
    where ss.ESPECIE = sa.ESPECIE 
      and ss.PRESENCIA > 0 
      and sa.PRESENCIA > 0) x
 where i.CARTA = x.CARTA
   and i.COD_SITTOT = x.AMBIENTE; 
 -- Esta es la tabla que sirve para consultar!

/* Luego la consulta es sobre el shape original de ambientes: cuando alguien
   hace click, se determina en qué polígono es y por lo tanto, qué AUTOID es,
   la cual sirve para ir a la tabla_consultas y ver qué especies hay, dando
   un resultaod del estilo:

   AUTOID COD_SITTOT ESPECIE
    29351 BaPPLLTNN  Hydrochaerus hydrochaeris
    29351 BaPPLLTNN  Myocastor coypus
    29351 BaPPLLTNN  Hoplias malabaricus
    ...

   Y de esta consulta se puede sacar la 3er columna para mandar a la app.
/*


