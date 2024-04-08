type 'a link
(** A pointer to an ['a] value, either residing in memory or on disk. *)

val link : 'a -> 'a link
(** [link v] returns a new link to the in-memory value [v]. *)

val fetch : 'a link -> 'a
(** [fetch lnk] returns the value pointed by the link [lnk].
  
    We of course have [fetch (link v) = v] and [link (fetch lnk) = lnk]. *)

(** For this demo we can't depend on a PPX or external dependencies,
    so we require a user-defined {!schema} to describe where the links can be
    found.  This is just an iter traversal over the values, recursively
    yielding on any reachable link. Since links can point to values themselves
    containing links, recursion is delayed by asking for the schema of each
    child.

    For example, the following type has the following schema:

    {[
      type t = { first : string link ; second : int link list link }

      let schema : t schema = fun iter t ->
        iter.yield t.first schema_no_sublinks ;
        iter.yield t.second @@ fun iter lst ->
          List.iter (fun v -> iter.yield v schema_no_sublinks) lst
    ]}

    where {!schema_no_sublinks} indicates that the yielded value contains
    no reachable links. *)

type 'a schema = iter -> 'a -> unit
(** A function to iter on every {!link} reachable in the value ['a]. *)

and iter = {yield: 'a. 'a link -> 'a schema -> unit}
(** A callback to signal the reachable links and the schema of their pointed
    sub-value.  Since a value can contain multiple links each pointing to
    different types of values, the callback is polymorphic. *)

val schema_no_sublinks : 'a schema
(** A schema usable when the ['a] value does not contain any links. *)

val write :
  ?flags:Marshal.extern_flags list -> string -> 'a schema -> 'a -> unit
(** [write filename schema value] writes the [value] in the file [filename],
    creating unmarshalling boundaries on every link in [value] specified
    by the [schema]. *)

type store
(** The type to represent an open disk connection. *)

val read : string -> 'a schema -> store * 'a
(** [read filename schema] reads the value marshalled in the file [filename],
    stopping the unmarshalling on every link boundary indicated by the [schema].
    It returns the open [store] and the root [value] read.  *)

val close : store -> unit
(** [close store] closes the connection to the disk. Any further {!fetch} requiring
    to read from the disk will fail. *)
