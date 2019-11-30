
module T = Gospel.Tast
open Why3
open Ptree
module Ot = Gospel.Oparsetree

type gdecl =
  | Gdecl of decl
  | Gmodule of ident * gdecl list

let location { Gospel.Location.loc_start = b; Gospel.Location.loc_end = e } =
  Loc.extract (b, e)

let dummy_loc = Loc.dummy_position

let get_opt_default f d = function None -> d | Some x -> f x

let mk_id id_str id_loc =
  { id_str; id_ats = []; id_loc }

let type_decl td = {
  td_loc    = location td.T.td_loc;
  td_ident  = assert false (*TODO*) (*ident*);
  td_params = assert false (*TODO*) (*ident list*);
  td_vis    = assert false (*TODO*) (*visibility*); (* records only *)
  td_mut    = assert false (*TODO*) (*bool*);       (* records or abstract types *)
  td_inv    = assert false (*TODO*) (*invariant*);  (* records only *)
  td_wit    = assert false (*TODO*) (*(qualid * expr) list*);
  td_def    = assert false (*TODO*) (*type_def*);
}

module Term = struct
  module Tt = Gospel.Tterm
  module Ty = Gospel.Ttypes
  module I  = Gospel.Identifier

  let mk_term term_desc term_loc =
    { term_desc; term_loc }

  let mk_pattern pat_desc pat_loc =
    { pat_desc; pat_loc }

  let ident_of_vsymbol Tt.{vs_name = name} =
    mk_id name.I.id_str (location name.I.id_loc)

  let quant = function
    | Tt.Tforall -> Dterm.DTforall
    | Tt.Texists -> Dterm.DTexists
    | Tt.Tlambda -> Dterm.DTlambda

  let (* rec *) pattern pat =
    let loc = get_opt_default location dummy_loc pat.Tt.p_loc in
    let mk_pattern pat_desc = mk_pattern pat_desc loc in
    let p_node = function
      | _ -> assert false (* TODO *) in
    mk_pattern (p_node pat.Tt.p_node)

  let rec ty Ty.{ty_node} = match ty_node with
    | Ty.Tyvar {tv_name} ->
        PTtyvar (mk_id tv_name.id_str (location tv_name.id_loc))
    | Ty.Tyapp ({ts_ident}, tyl) ->
        let qualid = mk_id ts_ident.id_str (location ts_ident.id_loc) in
        PTtyapp (Qident qualid, List.map ty tyl)

  let binder_of_vsymbol vs =
    let loc = vs.Tt.vs_name.I.id_loc in
    let id  = ident_of_vsymbol vs in
    let pty = ty vs.vs_ty in
    location loc, Some id, false, Some pty

  let param_of_vsymbol Tt.{vs_name; vs_ty} =
    let loc = location vs_name.I.id_loc in
    let id  = mk_id vs_name.I.id_str loc in
    let pty = ty vs_ty in
    loc, Some id, false, pty

  let binop = function
    | Tt.Tand      -> Dterm.DTand
    | Tt.Tand_asym -> Dterm.DTand_asym
    | Tt.Tor       -> Dterm.DTor
    | Tt.Tor_asym  -> Dterm.DTor_asym
    | Tt.Timplies  -> Dterm.DTimplies
    | Tt.Tiff      -> Dterm.DTiff

  let rec term t =
    let loc = get_opt_default location dummy_loc t.Tt.t_loc in
    let mk_term term_desc = mk_term term_desc loc in
    let t_node = function
      | Tt.Ttrue    -> Ttrue
      | Tt.Tfalse   -> Tfalse
      | Tt.Tvar vs  -> Tident (Qident (ident_of_vsymbol vs))
      | Tt.Tnot t   -> Tnot (term t)
      | Tt.Told t   -> Tat (term t, mk_id Dexpr.old_label loc)
      | Tt.Tconst c -> begin match c with
          | Pconst_integer (s, None) ->
              (* FIXME: check that [neg] parameter *)
              let n = Number.(int_literal ILitDec ~neg:false s) in
              Tconst (Constant.ConstInt n)
          | _ -> assert false (* TODO *) end
      | Tt.Tif (t1, t2, t3) ->
          Tif (term t1, term t2, term t3)
      | Tt.Tlet (vs, t1, t2) ->
          Tlet (ident_of_vsymbol vs, term t1, term t2)
      | Tt.Tcase (t, pat_term_list) ->
          let f_pair (pat, t) = pattern pat, term t in
          Tcase (term t, List.map f_pair pat_term_list)
      | Tt.Tquant (q, vs_list, trigger, t) ->
          let mk_trigger t = List.map term t in
          let trigger = List.map mk_trigger trigger in
          Tquant (quant q, List.map binder_of_vsymbol vs_list, trigger, term t)
      | Tt.Tbinop (op, t1, t2) ->
          Tbinop (term t1, binop op, term t2)
      | Tt.Tapp ({ls_name}, term_list) -> let loc = ls_name.I.id_loc in
          let term_list = List.map term term_list in
          let id = mk_id ls_name.I.id_str (location loc) in
          Tidapp (Qident id, term_list) in
    mk_term (t_node t.Tt.t_node)
end

let rec longident loc = function
  | Gospel.Longident.Lident s    -> Qident (mk_id s loc)
  | Gospel.Longident.Ldot (t, s) -> Qdot (longident loc t, mk_id s loc)
  | _ -> assert false (* TODO? *)

let mk_expr expr_desc expr_loc =
  { expr_desc; expr_loc }

let mk_logic_decl ld_loc ld_ident ld_params ld_type ld_def =
  { ld_loc; ld_ident; ld_params; ld_type = ld_type; ld_def }

let loc_of_vs vs = Term.(location vs.Tt.vs_name.I.id_loc)

let ident_of_lb_arg lb = Term.ident_of_vsymbol (T.vs_of_lb_arg lb)
let loc_of_lb_arg lb = loc_of_vs (T.vs_of_lb_arg lb)

(** Given the result type [sp_ret] of a function and a GOSPEL postcondition
    [post] (in the form of [term]), convert it into a Why3's Ptree
    postcondition of the form [Loc.position * (pattern * term)]. *)
let sp_post sp_ret post =
  let mk_post post =
    let pvar_of_lb_arg_list lb_arg_list =
      let mk_pvar lb = (* create a [Pvar] pattern out of a [Tt.lb_arg] *)
        Term.mk_pattern (Pvar (ident_of_lb_arg lb)) dummy_loc in
      List.map mk_pvar lb_arg_list in
    let pat = match pvar_of_lb_arg_list sp_ret with
      | [p] -> p
      | pl  -> Term.mk_pattern (Ptuple pl) dummy_loc in
    dummy_loc, [pat, Term.term post] in
  List.map mk_post post

open Term

(** Convert a GOSPEL exception postcondition of the form
    [(pattern * post) list Mxs.t] into a Why3's Ptree exceptional
    postcondition of the form
    [Loc.position * (qualid * (pattern * term) option) list]. *)
let sp_xpost xpost =
  let mk_xpost_list xs pat_post_list acc =
    let loc = xs.Ty.xs_ident.I.id_loc in
    let mk_xpost (_pat, post) =
      let q = Qident (mk_id xs.Ty.xs_ident.I.id_str (location loc)) in
      let post = term post in
      q, Some (mk_pattern (Ptuple []) dummy_loc, post) in
    (location loc, List.map mk_xpost pat_post_list) :: acc in
  Ty.Mxs.fold mk_xpost_list xpost []

let sp_writes writes =
  List.map term writes

let spec val_spec = {
  (* TODO: for now, we ignore the [checks] preconditions *)
  sp_pre     = List.map (fun (t, _) -> term t) val_spec.T.sp_pre;
  sp_post    = sp_post val_spec.sp_ret val_spec.sp_post;
  sp_xpost   = sp_xpost val_spec.sp_xpost;
  sp_reads   = [];
  sp_writes  = sp_writes val_spec.sp_wr;
  sp_alias   = [];
  sp_variant = [];
  sp_checkrw = false;
  sp_diverge = false;
  sp_partial = false;
}

let empty_spec = {
  sp_pre     = [];
  sp_post    = [];
  sp_xpost   = [];
  sp_reads   = [];
  sp_writes  = [];
  sp_alias   = [];
  sp_variant = [];
  sp_checkrw = false;
  sp_diverge = false;
  sp_partial = false;
}

let rec core_type Ot.{ ptyp_desc; ptyp_loc } =
  match ptyp_desc with
  | Ptyp_var x ->
      PTtyvar (mk_id x (location ptyp_loc))
  | Ptyp_arrow (_, ty1, ty2) ->
      PTarrow (core_type ty1, core_type ty2)
  | Ptyp_tuple ctl ->
      PTtuple (List.map core_type ctl)
  | Ptyp_constr ({txt; loc}, ctl) ->
      PTtyapp (longident (location loc) txt, List.map core_type ctl)
  | _ -> assert false (* TODO *)

(** Convert GOSPEL val declarations into Why3's Ptree [val] declarations. *)
let val_decl vd g =
  let rec flat_ptyp_arrow ct = match ct.Ot.ptyp_desc with
    | Ot.Ptyp_var _ | Ptyp_tuple _ | Ptyp_constr _ -> [ct]
    | Ot.Ptyp_arrow (_, t1, t2) -> flat_ptyp_arrow t1 @ flat_ptyp_arrow t2
    | _ -> assert false (* TODO *) in
  let mk_param lb_arg ct =
    let loc = Term.(location (T.vs_of_lb_arg lb_arg).vs_name.I.id_loc) in
    let id, ghost = match lb_arg with
      | Lnone _  -> Some (ident_of_lb_arg lb_arg), false
      | Lghost _ -> Some (ident_of_lb_arg lb_arg), true
      | _ -> assert false in
    loc, id, ghost, core_type ct in
  let mk_param_no_spec ct =
    let loc = location ct.Ot.ptyp_loc in
    loc, None, false, core_type ct in
  let param_list, ret, pat, mask, spec =
    let core_ty_list = flat_ptyp_arrow vd.T.vd_type in
    let core_ty_list, last = Lists.chop_last core_ty_list in
    let param_list, pat, mask, spec = match vd.T.vd_spec with
    | None -> let param_list = List.map mk_param_no_spec core_ty_list in
        (* when there is no specification, there is no pattern
           in the return tuple *)
        let pat = Term.mk_pattern Pwild (location last.Ot.ptyp_loc) in
        param_list, pat, Ity.MaskVisible, empty_spec
    | Some s -> let param_list = List.map2 mk_param s.T.sp_args core_ty_list in
        let mk_pat lb = let loc = loc_of_lb_arg lb in
          Term.mk_pattern (Pvar (ident_of_lb_arg lb)) loc in
        let mk_mask = function
          | T.Lnone  _ -> Ity.MaskVisible
          | T.Lghost _ -> Ity.MaskGhost
          | _          -> assert false in
        let lb_list = s.T.sp_ret in
        let pat_list  = List.map mk_pat lb_list in
        let mask_list = List.map mk_mask lb_list in
        let pat, mask = match pat_list, mask_list with
          | [], [] -> assert false
          | [p], [m] -> p, m
          | pl, ml   -> assert (List.length pl = List.length ml);
              let loc = location vd.T.vd_loc in (* TODO: better location? *)
              Term.mk_pattern (Ptuple pl) loc, Ity.MaskTuple ml in
        param_list, pat, mask, spec s in
    param_list, Some (core_type last), pat, mask, spec in
  let e_any  = Eany (param_list, Expr.RKnone, ret, pat, mask, spec) in
  let e_any  = mk_expr e_any (location vd.T.vd_loc) in
  let id_loc = location vd.vd_name.id_loc in
  Dlet (mk_id vd.vd_name.id_str id_loc, g, Expr.RKnone, e_any)

(** Convert GOSPEL logical declaration (function or predicate) into
     Why3's Ptree logical declaration. *)
let function_ (T.{fun_ls = Tt.{ls_name; ls_value}} as f) =
  let loc = location f.T.fun_loc in
  let id_loc = location ls_name.I.id_loc in
  let id = mk_id ls_name.I.id_str id_loc in
  let params = List.map param_of_vsymbol f.fun_params in
  let pty = Opt.map ty ls_value in
  let term = Opt.map term f.T.fun_def in
  Dlogic [mk_logic_decl loc id params pty term]

(** Convert GOSPEL axioms into Why3's Ptree axioms. *)
let axiom T.{ax_name; ax_term} =
  let id_loc = location ax_name.I.id_loc in
  let id = mk_id ax_name.I.id_str id_loc in
  let term = term ax_term in
  Dprop (Decl.Paxiom, id, term)

let signature_item i = match i.T.sig_desc with
  (* GOSPEL-modified decls *)
  | T.Sig_val (vd, g) ->
      [Gdecl (val_decl vd g)]
  | T.Sig_type (_rec_flag, tdl, _gh) ->
      [Gdecl (Dtype (List.map type_decl tdl))]
  | T.Sig_typext _ (*  of Oparsetree.type_extension *) ->
      assert false (*TODO*)
  | T.Sig_module _ (*  of module_declaration *) ->
      assert false (*TODO*)
  | T.Sig_recmodule _ (* of module_declaration list *) ->
      assert false (*TODO*)
  | T.Sig_modtype _ (*  of module_type_declaration *) ->
      assert false (*TODO*)
  (* OCaml decls *)
  | T.Sig_exception _ (* of type_exception *) ->
      assert false (*TODO*)
  | T.Sig_open _ (* of open_description * ghost *) ->
      (* The GOSPEL standard library is opened by default. For now, we chose to
         ignore it and will make a work-around with a custom Why3 file. *)
      [] (*TODO*)
  | T.Sig_include _ (* of Oparsetree.include_description *) ->
      assert false (*TODO*)
  | T.Sig_class _ (* of Oparsetree.class_description list *) ->
      assert false (*TODO*)
  | T.Sig_class_type _ (* of Oparsetree.class_type_declaration list *) ->
      assert false (*TODO*)
  | T.Sig_attribute _ (* of Oparsetree.attribute *) ->
      assert false (*TODO*)
  | T.Sig_extension _ (* of Oparsetree.extension * Oparsetree.attributes *) ->
      assert false (*TODO*)
  (* GOSPEL-specific decls *)
  | T.Sig_use _ (* of string *) ->
      assert false (*TODO*)
  | T.Sig_function f ->
      [Gdecl (function_ f)]
  | T.Sig_axiom ax ->
      [Gdecl (axiom ax)] (*TODO*)

let signature = List.map signature_item
