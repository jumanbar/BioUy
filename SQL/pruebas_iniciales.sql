/*
SELECT 
  id, sc, geoformas, carac_inun, cod_sittot
FROM 
  public.ambientes_ppr 
WHERE ambientes_ppr.cod_sittot = 'PrPPMLHNN'
LIMIT 30
 ; --33692

--select count(*) from public.ambientes_ppr; --33692

select
  id,
  cod_sittot as ambiente,
  st_area(geom) / 10000 as hectareas
from
  public.ambientes_ppr
--where
--  ambientes_ppr.cod_sittot = 'PrPPMLHNN'
order by hectareas desc
LIMIT 30;

--*/
--drop table ambiente_cartas;
--create table public.ambiente_cartas as
/*
select
  ppr.id as id_ppr, ppr.cod_sittot,
  sgm.id as id_sgm, sgm.carta, sgm.nombre
  --, ST_Intersection(ppr.geom, sgm.geom) -- Para obtener el área de intersección... pero no hace falta acá me parece
from
  public.ambientes_ppr ppr,
  public.cartas_sgm sgm
where
  --sgm.carta = 'H12' and
  st_intersects(ppr.geom, sgm.geom) -- ESTA ES LA POSTA!!
order by ppr.id, sgm.id
limit 30
;
commit;
--select * from ambiente_cartas;

*/

DROP TABLE species;
CREATE table species (
  id bigserial primary key,
  spp_group varchar(64) null,
  spp_order varchar(64) null,
  family varchar(128) null,
  sci_gen varchar(128) null, -- Género del nombre científico
  sci_spe varchar(128) null, -- Epíteto del nombre científico
  sci_sub varchar(128) null, -- Subespecie del nombre científico
  com_name varchar(512) null, -- Nombres comunes
  code varchar(64) null,
  cons_state varchar(64) null,
  native boolean null
);

CREATE index ix_spp_id on species (id);
CREATE index ix_spp_id_gen on species (id, sci_gen);
CREATE index ix_spp_gen_spp on species (sci_gen, sci_spe);

--select spp_group from species;

delete from species;

INSERT into species (spp_group, spp_order, family, sci_gen, sci_spe, com_name, code, cons_state, native) VALUES ('Anélidos','Canalipalpata','Serpulidae','Ficopomatus','enigmaticus','poliqueto incrustante','Fic_enigm','No evaluada','false');

select * from species;

 


