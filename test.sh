#!/bin/bash

echo '## Marshal'
dune exec --profile=release -- ./test_marshal.exe

echo
echo '## Granular Marshal'
dune exec --profile=release -- ./test_granular.exe
diff db.marshal.queries db.granular.queries

echo
echo '## Granular Marshal with Filename sharing'
dune exec --profile=release -- ./test_granular_dag.exe
diff db.marshal.queries db.granular_dag.queries

echo
echo '## Granular Marshal with Filename sharing and granular Map'
dune exec --profile=release -- ./test_granular_dag_map.exe
diff db.marshal.queries db.granular_dag_map.queries

echo
echo '## Granular Marshal with Filename sharing and less granular Map'
dune exec --profile=release -- ./test_granular_dag_map2.exe
diff db.marshal.queries db.granular_dag_map2.queries
