
# Importar el mapa ppr_biomes_dump a la base de grass, bajo el nombre "biomes".
# Es muy lento, capaz que lleva un día entero...
# (Grass inicializado...)

v.in.ogr input=PG:dbname=biouy layer=ppr_biomes_dump output=biomes \
  geometry=geom -c -e


#### Ejemplo de salida:
# GRASS 7.0.3 (BioUy):~ > v.in.ogr input=PG:dbname=biouy layer=ppr_biomes_dump output=biomes geometry=geom -c -e
# Check if OGR layer <ppr_biomes_dump> contains polygons...
#  100%
# Importing 6937193 features (OGR layer <ppr_biomes_dump>)...
#  100%
# -----------------------------------------------------
# Building topology for vector map <biomes@jmb>...
# Registering primitives...
# 17293898 primitives registered
# 132802372 vertices registered
# Building areas...
#  100%
# 10190333 areas built
# 9348022 isles built
# Attaching islands...
#  100%
# Attaching centroids...
#  100%
# Number of nodes: 9432216
# Number of primitives: 17293898
# Number of points: 0
# Number of lines: 0
# Number of boundaries: 10357167
# Number of centroids: 6936731

