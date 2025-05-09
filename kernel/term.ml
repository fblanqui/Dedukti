open Basic
open Format

(** {2 Terms/Patterns} *)

type term =
  | Kind (* Kind *)
  | Type of loc (* Type *)
  | DB of loc * ident * int (* deBruijn *)
  | Const of loc * name (* Global variable *)
  | App of term * term * term list (* f a1 [ a2 ; ... an ] , f not an App *)
  | Lam of loc * ident * term option * term (* Lambda abstraction *)
  | Pi of loc * ident * term * term
(* Pi abstraction *)

let rec pp_term fmt te =
  match te with
  | Kind -> fprintf fmt "Kind"
  | Type _ -> fprintf fmt "Type"
  | DB (_, x, n) -> fprintf fmt "%a[%i]" pp_ident x n
  | Const (_, n) -> fprintf fmt "%a" pp_name n
  | App (f, a, args) -> pp_list " " pp_term_wp fmt (f :: a :: args)
  | Lam (_, x, None, f) -> fprintf fmt "%a => %a" pp_ident x pp_term f
  | Lam (_, x, Some a, f) ->
      fprintf fmt "%a:%a => %a" pp_ident x pp_term_wp a pp_term f
  | Pi (_, x, a, b) when ident_eq x dmark ->
      fprintf fmt "%a -> %a" pp_term_wp a pp_term b
  | Pi (_, x, a, b) ->
      fprintf fmt "%a:%a -> %a" pp_ident x pp_term_wp a pp_term b

and pp_term_wp fmt te =
  match te with
  | (Kind | Type _ | DB _ | Const _) as t -> pp_term fmt t
  | t -> fprintf fmt "(%a)" pp_term t

let rec get_loc (te : term) : loc =
  match te with
  | Type l | DB (l, _, _) | Const (l, _) | Lam (l, _, _, _) | Pi (l, _, _, _) ->
      l
  | Kind -> dloc
  | App (f, _, _) -> get_loc f

let mk_Kind = Kind

let mk_Type l = Type l

let mk_DB l x n = DB (l, x, n)

let mk_Const l n = Const (l, n)

let mk_Lam l x a b = Lam (l, x, a, b)

let mk_Pi l x a b = Pi (l, x, a, b)

let mk_Arrow l a b = Pi (l, dmark, a, b)

let mk_App f a1 args =
  match f with
  | App (f', a1', args') -> App (f', a1', args' @ (a1 :: args))
  | _ -> App (f, a1, args)

let mk_App2 f = function [] -> f | hd :: tl -> mk_App f hd tl

let rec add_n_lambdas n t =
  if n = 0 then t else add_n_lambdas (n - 1) (mk_Lam dloc dmark None t)

let rec term_eq t1 t2 =
  (* t1 == t2 || *)
  match (t1, t2) with
  | Kind, Kind | Type _, Type _ -> true
  | DB (_, _, n), DB (_, _, n') -> n == n'
  | Const (_, cst), Const (_, cst') -> name_eq cst cst'
  | App (f, a, l), App (f', a', l') -> (
      try List.for_all2 term_eq (f :: a :: l) (f' :: a' :: l') with _ -> false)
  | Lam (_, _, _, b), Lam (_, _, _, b') -> term_eq b b'
  | Pi (_, _, a, b), Pi (_, _, a', b') -> term_eq a a' && term_eq b b'
  | _, _ -> false

type 'a comparator = 'a -> 'a -> int

let rec compare_term id_comp t1 t2 =
  match (t1, t2) with
  | Kind, Kind -> 0
  | Type _, Type _ -> 0
  | Const (_, name), Const (_, name') -> id_comp name name'
  | DB (_, _, n), DB (_, _, n') -> compare n n'
  | App (f, a, ar), App (f', a', ar') ->
      let c = compare_term id_comp f f' in
      if c <> 0 then c
      else
        let c = compare_term id_comp a a' in
        if c <> 0 then c else compare_term_list id_comp ar ar'
  | Lam (_, _, _, t), Lam (_, _, _, t') -> compare_term id_comp t t'
  | Pi (_, _, a, b), Pi (_, _, a', b') ->
      let c = compare_term id_comp a a' in
      if c = 0 then compare_term id_comp b b' else c
  | _, Kind -> 1
  | Kind, _ -> -1
  | _, Type _ -> 1
  | Type _, _ -> -1
  | _, Const _ -> 1
  | Const _, _ -> -1
  | _, DB _ -> 1
  | DB _, _ -> -1
  | _, App _ -> 1
  | App _, _ -> -1
  | _, Lam _ -> 1
  | Lam _, _ -> -1

and compare_term_list id_comp a b =
  match (a, b) with
  | [], [] -> 0
  | _, [] -> 1
  | [], _ -> -1
  | h :: t, h' :: t' ->
      let c = compare_term id_comp h h' in
      if c = 0 then compare_term_list id_comp t t' else c

type algebra = Free | AC | ACU of term

let is_AC = function AC -> true | ACU _ -> true | Free -> false

type position = int list

exception InvalidSubterm of term * int

let subterm t i =
  match t with
  | App (f, _, _) when i = 0 -> f
  | App (_, a, _) when i = 1 -> a
  | App (_, _, args) -> (
      try List.nth args (i - 2) with _ -> raise (InvalidSubterm (t, i)))
  | Lam (_, _, _, f) when i = 1 -> f
  | Lam (_, _, Some a, _) when i = 0 -> a
  | Pi (_, _, a, _) when i = 0 -> a
  | Pi (_, _, _, b) when i = 1 -> b
  | _ -> raise (InvalidSubterm (t, i))

let subterm = List.fold_left subterm

type cstr = int * term * term

let pp_cstr fmt (depth, t1, t2) =
  Format.fprintf fmt "[%i] %a = %a" depth pp_term t1 pp_term t2

(*********** Contexts} ***********)

type 'a context = (loc * ident * 'a) list

type partially_typed_context = term option context

type typed_context = term context

type arity_context = int context

type 'a depthed = int * 'a

let pp_untyped_ident fmt (_, id, _) = Format.fprintf fmt "%a" pp_ident id

let pp_typed_ident fmt (_, id, ty) =
  Format.fprintf fmt "%a:%a" pp_ident id pp_term ty

let pp_maybe_typed_ident fmt (l, id, ty) =
  match ty with
  | None -> pp_untyped_ident fmt (l, id, ())
  | Some ty -> pp_typed_ident fmt (l, id, ty)

let pp_context pp_i fmt l = fprintf fmt "[%a]" (pp_list ", " pp_i) (List.rev l)

let pp_untyped_context fmt = pp_context pp_untyped_ident fmt

let pp_typed_context = pp_context pp_typed_ident

let pp_part_typed_context = pp_context pp_maybe_typed_ident

let get_name_from_typed_ctxt ctxt i =
  try
    let _, v, _ = List.nth ctxt i in
    Some v
  with Failure _ -> None

let rename_vars_with_typed_context ctxt t =
  let rec aux d t =
    match t with
    | DB (l, _, n) when n > d -> (
        match get_name_from_typed_ctxt ctxt (n - d) with
        | Some v' -> mk_DB l v' n
        | None -> t)
    | App (f, a, args) -> mk_App (aux d f) (aux d a) (List.map (aux d) args)
    | Lam (l, x, ty, f) -> mk_Lam l x (map_opt (aux d) ty) (aux (d + 1) f)
    | Pi (l, x, ty, b) -> mk_Pi l x (aux d ty) (aux (d + 1) b)
    | _ -> t
  in
  aux 0 t
