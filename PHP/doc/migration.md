# Preconditions: Database 'biouy' must be created and postgis extension enabled.

# Import shapefiles into DB.
shp2pgsql -c -D -s 32721 -i -I data/shapefiles/utm_grid/utm_grid.shp public.utm_grid | psql -h 127.0.0.1 -p 54320 -U homestead -d biouy
shp2pgsql -c -D -s 32721 -i -I data/shapefiles/ppr_site/ppr_site.shp public.ppr_site | psql -h 127.0.0.1 -p 54320 -U homestead -d biouy

# Execute the following sql statements
-- Refactor imported tables
ALTER TABLE ppr_site RENAME COLUMN auto_id TO external_id;
ALTER TABLE utm_grid RENAME COLUMN id_ TO external_id;

-- Species table creation
CREATE TABLE species (
  id serial primary key,
  spp_group varchar(64) null,
  spp_order varchar(64) null,
  family varchar(128) null,
  sci_gen varchar(128) null,  -- Género del nombre científico
  sci_spe varchar(128) null,  -- Epíteto del nombre científico
  sci_sub varchar(128) null,  -- Subespecie del nombre científico
  com_name varchar(512) null, -- Nombres comunes
  code varchar(64) null,
  cons_state varchar(64) null,
  native boolean null
);

CREATE index ix_spp_id on species (id);
CREATE index ix_spp_id_gen on species (id, sci_gen);
CREATE index ix_spp_gen_spp on species (sci_gen, sci_spe);

-- Species by utm table creation
CREATE TABLE utm_species (
  id serial primary key,
  utm_id integer REFERENCES utm_grid(gid),
  species_id integer REFERENCES species (id)
);

-- Species by ppr table creation
CREATE TABLE ppr_type_species (
  id serial primary key,
  ppr_type_id integer REFERENCES ppr_site(gid),
  species_id integer REFERENCES species (id)
);

-- Ppr site type table creation
CREATE TABLE ppr_site_type (
    id serial primary key,
    code character varying(30)
);

-- Add type column to ppr sites table.
ALTER TABLE ppr_site ADD COLUMN type integer REFERENCES ppr_site_type(id);

# Import species and distribution
$ php snapToSql.php

# Execute the following sql statements
-- Insert ppr site types.
INSERT into ppr_site_type (code) SELECT DISTINCT cod_sittot FROM ppr_site;

-- Update type columns
UPDATE ppr_site s SET type = (SELECT t.id FROM ppr_site_type t WHERE t.code = s.cod_sittot limit 1);

# Backup and restore data
/usr/bin/pg_dump --host 127.0.0.1 --port 54320 --username "homestead" --no-password  --format custom --blobs -O -x  --verbose --file "/tmp/biouybkp" "biouy"
/usr/bin/pg_restore --host 127.0.0.1 --port 54320 --username "homestead" --dbname "biouy" --no-password  --verbose "/tmp/biouybkp"
