A quick test to see the impact of a more granular Marshal [`granular_marshal.ml`](granular_marshal.ml) for an existing application currently using the stdlib `Marshal`. Do not use, this is just an internal report to showcase the interface [`granular_marshal.mli`](granular_marshal.mli) that the Irmin team has been thinking about at Tarides.

All the tests follow the same steps: (with a deterministic use of random, so exact same database and queries to allow comparison)

1. Create a random "reverse index" search database in memory, with 1 million distinct values each having 1-100 occurrences in 100k files
2. Write the database to disk
3. Read the database from disk
4. Perform 1k occurrence queries on it

In the application we are considering, steps 1-2 are performed by an "indexer" process frequently. Once a fresh new DB has been written to disk, a separate "server" process must reload it (step 3) to continuously answer user queries (step 4). We don't want to change this architecture or introduce new dependencies, we are only trying to reduce the step 3 overhead to ensure queries are answered without delays.

Non-scientific benchmarks outcomes on my machine, which you can reproduce with `./test.sh`:

| Test                            |    DB generation | Write to disk | Read from disk | 1k Queries |     DB filesize |
|:------------------------------- | ----------------:| -------------:| --------------:| ----------:| ---------------:|
| Marshal                         |           3.371s |        3.211s |         0.778s |     0.467s |           175Mb |
| Granular Marshal (naive)        |           3.409s |        2.127s |         0.268s |     0.029s | :warning: 506Mb |
| Granular with Filename sharing  |           3.486s |        2.239s |         0.212s |     0.098s |           232Mb |
| Granular with granular Map      | :warning: 5.353s |        2.704s |         0.000s |     0.156s |           284Mb |
| Granular with less granular Map |           3.714s |        2.021s |         0.000s |     0.127s |           233Mb |

**[`test_marshal.ml`](test_marshal.ml) is the baseline test,** only using `Marshal` to serialize/deserialize the full database in one go. It uses the following simplified database which is supposed to look like the real application "reverse index" search DB:

```ocaml
module M = Map.Make (String)
type loc = { filename : string; line : int }
type db = loc list M.t
```

i.e. the database is a map associating each word to the list of locations where it can be found. We can query the database by printing the occurrences of any identifier:

```ocaml
let query db word =
  let occurrences = M.find word db in
  List.iter (fun loc -> Format.printf "- %s:%i@." loc.filename loc.line) occurrences
```

As expected, opening the database is a bit slow at ~800ms since it must unmarshal the full database in one go.

**[`test_granular.ml`](test_granular.ml) shows a basic usage of the granular Marshal,** by just adding a `link` boundary on the list of locations to delay their unmarshalling:

```ocaml
module M = Map.Make (String)
type loc = { filename : string; line : int }
type db = loc list link M.t
(*                 ^^^^     *)
```

This new `link` annotation introduces a boundary to stop the unmarshalling process. In other words, opening the database will only unmarshal the map, but not the occurrences lists. We'll need to explicitly `fetch : 'a link -> 'a` the values pointed by a link during the queries, such that their unmarshalling is lazy / on-demand (and cached):

```ocaml
let query db value_name =
  let occurrences = M.find value_name db in
  List.iter
    (fun loc -> Format.printf "- %s:%i@." loc.filename loc.line)
    (fetch occurrences)
(*   ^^^^^              *)
```

This simple `link` annotation cuts down the time to read the database from 778ms to 286ms, and more surprisingly writing the db to disk from 3.2s downto 2.1s!.. However the size of the database explodes from 175MB to 506Mb: We have lost the sharing of filenames that was present in the previous version. The global Marshal could serialize a loc's `filename` once and reuse it everywhere, while the granular version can't cross marshalling boundaries without links.

**[`test_granular_dag.ml`](test_granular_dag.ml) reintroduces the filename sharing,** by annotating them with a `link` too:

```ocaml
module M = Map.Make (String)
type loc = { filename : string link ; line : int }
(*                             ^^^^                *)
type db = loc list link M.t
```

This doesn't change too much the time to write/read the database from disk, but it does reduce the db filesize to the more acceptable 232Mb. We now have the same sharing as in the raw `Marshal` version, but the db is still bigger because each `link` boundary must pay for the [`Marshal.header_size`](https://v2.ocaml.org/releases/5.1/api/Marshal.html#VALheader_size) and some extra bytes per link.

The initial time to read the db is still ~200ms because we still have to unmarshal the big Map, so let's see if we can cut that down further:

**[`test_granular_dag_map.ml`](test_granular_dag_map.ml) changes the `Map` implementation to be more granular,** by adding `link` annotations in OCaml's stdlib `Map`: the refactoring is type-driven so very straightforward... but now opening the database is free! (since the Map will be unmarshalled by very small pieces at a time during queries' execution)

```ocaml
module M = Map_granular.Make (String)
(*            ^^^^^^^^^               *)
type loc = { filename : string link; line : int }
type db = loc list link M.t
```

However, adding `link` indirections everywhere in the stdlib `Map` causes the DB generation in-memory to be 2s slower! This is because the stdlib `Map` is a binary AVL tree, so we end up with links everywhere on our way. Links representation is cheap, but too much of them is too much and the overhead is still felt.

We could improve this by making the `Map` wider (= with less links), or by optimizing the String Map representation with a Trie datastructure (... but this may not be relevant for the considered application's actual representation of its index, so we leave it as an exercice for later).

**[`test_granular_dag_map2.ml`](test_granular_dag_map2.ml) adds less `link` into the Stdlib Map,** for the sake of ending on an overall positive note: not too much in-memory overhead from having too many `link` indirections, fast writes, fast reads, fast queries, reasonnable filesize. The implementation is incomplete, but may actually be enough for the considered application.

Personal takeaways from these experiments:

- As expected, the granular unmarshalling can be super fast at opening the DB without negatively impacting query time.
- It can also speed up writing the DB to disk!
- On-demand lazy loading lower the stress on memory compared to loading everything at once.
- The database size on disk will be slightly bigger, because we need to write more metadatas for the granular unmarshalling to work. Playing with the links granularity will help and custom optims could be added to further reduce the filesize.
- It's not 100% obvious how to slice the database into efficient pieces for unmarshalling: The `link/fetch` interface prooved very convenient to quickly experiment with different strategies in a type-driven fashion.
- A custom fileformat (not using Marshal at all) could result in smaller file sizes and faster file writes... but at the cost of taking more time to be developed and maintained. Until this become critical, the granular marshal seems like a good compromise!

Stuff we left out of this demo:
- No PPX for the DB schema! Instead we require users to write an `iter`-like function to traverse the values and tell us where all the links are. It's a chore but short enough that it should not be too tedious.
- Not thread-safe: this likely needs to be added in a real implementation to handle async queries.
- Once written to disk, links are broken and can't be fetched anymore: we should consider repairing them, unless the indexer process doesn't need it.
- No deduplication or LRU to free memory or incremental write updates or... well no fancy secret sauce really. After all, it's only 80 lines of code with no dependencies, eh.
