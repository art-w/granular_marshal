open Granular_marshal

let db_name = "db.granular_dag_map2"

let nb_values = 1_000_000

let nb_files = 100_000

module M = Map_granular2.Make (String)

type loc = {filename: string link; line: int}

type db = loc list link M.t

let query ~out db value_name =
  let occurrences = M.find value_name db in
  List.iter
    (fun loc -> Format.fprintf out "- %s:%i@." (fetch loc.filename) loc.line)
    (fetch occurrences)

let schema_locs iter locs =
  List.iter (fun loc -> iter.yield loc.filename schema_no_sublinks) locs

let schema iter db = M.schema iter (fun _ v -> iter.yield v schema_locs) db

(* Random DB generation *)

let t0 = Unix.gettimeofday ()

let () = Random.init 0

let random_elt arr = arr.(Random.int (Array.length arr))

let random_name () =
  String.init
    (10 + Random.int 30)
    (fun _ -> Char.chr (Char.code 'a' + Random.int 26))

let random_valuenames = Array.init nb_values (fun _ -> random_name ())

let random_filenames = Array.init nb_files (fun _ -> link (random_name ()))

let random_file () = random_elt random_filenames

let my_db =
  M.granular @@ M.of_seq @@ Array.to_seq
  @@ Array.map
       (fun value_name ->
         ( value_name
         , link
           @@ List.init
                (1 + Random.int 30)
                (fun _ -> {filename= random_file (); line= Random.int 1000}) )
         )
       random_valuenames

let t1 = Unix.gettimeofday ()

let () = Format.printf "Created db in %.3fs@." (t1 -. t0)

(* Write DB to disk *)

let () =
  let t0 = Unix.gettimeofday () in
  Granular_marshal.write db_name schema my_db ;
  let t1 = Unix.gettimeofday () in
  Format.printf "Wrote database in %.3fs@." (t1 -. t0)

(* Read DB from disk *)

let store, db =
  let t0 = Unix.gettimeofday () in
  let store, (db : db) = Granular_marshal.read db_name schema in
  let t1 = Unix.gettimeofday () in
  Format.printf "Read database in %.3fs@." (t1 -. t0) ;
  Format.printf "Database size in-memory: %#iKb@."
    (Obj.reachable_words (Obj.repr db) / 1024) ;
  store, db

(* Query DB *)

let () =
  let debug = open_out (db_name ^ ".queries") in
  let out = Format.formatter_of_out_channel debug in
  let t0 = Unix.gettimeofday () in
  for _ = 1 to 1_000 do
    let my_query = random_elt random_valuenames in
    query ~out db my_query
  done ;
  let t1 = Unix.gettimeofday () in
  close_out debug ;
  Format.printf "1k Queries in %.3fs@." (t1 -. t0) ;
  Format.printf "Database size in-memory after queries: %#iKb@."
    (Obj.reachable_words (Obj.repr db) / 1024)

let () =
  Format.printf "DB filesize = %#iMb@."
    ((Unix.stat db_name).st_size / (1024 * 1024))

let () = Granular_marshal.close store
