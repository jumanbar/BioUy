while read p; do
  echo $p
  sed "3s/XXX/$p/" template.sql > run.sql
  exit
done <lista.txt
