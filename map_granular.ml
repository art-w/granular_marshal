(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Granular_marshal

module type OrderedType = sig
  type t

  val compare : t -> t -> int
end

module type S = sig
  type key

  type !+'a t

  val find : key -> 'a t -> 'a

  val of_seq : (key * 'a) Seq.t -> 'a t

  val schema : iter -> (key -> 'a -> unit) -> 'a t -> unit
end

module Make (Ord : OrderedType) = struct
  type key = Ord.t

  type 'a s = Empty | Node of {l: 'a t; v: key; d: 'a; r: 'a t; h: int}

  and 'a t = 'a s link

  let height t =
    match fetch t with
    | Empty -> 0
    | Node {h} -> h

  let create l x d r =
    let hl = height l and hr = height r in
    link (Node {l; v= x; d; r; h= (if hl >= hr then hl + 1 else hr + 1)})

  let empty () = link Empty

  let singleton x d = link (Node {l= empty (); v= x; d; r= empty (); h= 1})

  let bal l x d r : _ t =
    let hl = height l in
    let hr = height r in
    if hl > hr + 2
    then
      match fetch l with
      | Empty -> invalid_arg "Map.bal"
      | Node {l= ll; v= lv; d= ld; r= lr} -> (
          if height ll >= height lr
          then create ll lv ld (create lr x d r)
          else
            match fetch lr with
            | Empty -> invalid_arg "Map.bal"
            | Node {l= lrl; v= lrv; d= lrd; r= lrr} ->
                create (create ll lv ld lrl) lrv lrd (create lrr x d r) )
    else if hr > hl + 2
    then
      match fetch r with
      | Empty -> invalid_arg "Map.bal"
      | Node {l= rl; v= rv; d= rd; r= rr} -> (
          if height rr >= height rl
          then create (create l x d rl) rv rd rr
          else
            match fetch rl with
            | Empty -> invalid_arg "Map.bal"
            | Node {l= rll; v= rlv; d= rld; r= rlr} ->
                create (create l x d rll) rlv rld (create rlr rv rd rr) )
    else link (Node {l; v= x; d; r; h= (if hl >= hr then hl + 1 else hr + 1)})

  let rec add x data m : _ t =
    match fetch m with
    | Empty -> singleton x data
    | Node {l; v; d; r; h} ->
        let c = Ord.compare x v in
        if c = 0
        then if d == data then m else link (Node {l; v= x; d= data; r; h})
        else if c < 0
        then
          let ll = add x data l in
          if l == ll then m else bal ll v d r
        else
          let rr = add x data r in
          if r == rr then m else bal l v d rr

  let rec find x m =
    match fetch m with
    | Empty -> raise Not_found
    | Node {l; v; d; r} ->
        let c = Ord.compare x v in
        if c = 0 then d else find x (if c < 0 then l else r)

  let add_seq i m = Seq.fold_left (fun m (k, v) -> add k v m) m i

  let of_seq i = add_seq i (empty ())

  let rec schema iter f m =
    iter.yield m
    @@ fun iter tree ->
    match tree with
    | Empty -> ()
    | Node {l; v; d; r} -> schema iter f l ; f v d ; schema iter f r
end
