open Kernel
open Api
open Cmdliner

let export =
  let doc =
    "Generate object files (\".dko\"). Object files are written in the same \
     directory as the source file."
  in
  Arg.(value & flag & info ["e"] ~doc)

let beautify =
  (* TODO put in a separate command. *)
  let doc = "Pretty print a file on the standard input" in
  Arg.(value & flag & info ["beautify"] ~doc)

let de_bruijn =
  let doc = "Print de Bruijn indices in error messages" in
  Arg.(value & flag & info ["db"] ~doc)

let confluence =
  let doc =
    "Use $(docv) as external confluence checker. $(docv) must be a readable \
     file."
  in
  Arg.(
    value & opt (some string) None & info ["cc"; "confluence"] ~doc ~docv:"CMD")

let files =
  let doc = "Dedukti files to type check" in
  Arg.(value & pos_all string [] & info [] ~docv:"FILE" ~doc)

let eta =
  let doc = "Enable conversion modulo eta" in
  Arg.(value & flag & info ["eta"] ~doc)

let ll =
  let doc = "Check left linearity of rewrite rules" in
  Arg.(value & flag & info ["ll"] ~doc)

let sr_check =
  let doc =
    "Set the level of subject reduction checking to $(docv). Default value is \
     1, values < 0 may not terminate on rules that do not preserve typing."
  in
  Arg.(value & opt int 1 & info ["sr-check"] ~doc ~docv:"LVL")

let errors_in_snf =
  let doc = "Normalize terms in error messages" in
  Arg.(value & flag & info ["errors-in-snf"] ~doc)

let coc =
  let doc =
    "$(b,EXPERIMENTAL) Allows declaring symbols whose type contains Type in \
     the left-hand side of a product (similar to the logic of the Calculus of \
     Constructions)"
  in
  Arg.(value & flag & info ["coc"] ~doc)

let type_lhs =
  let doc = "Forbid rules with untypable left-hand side" in
  Arg.(value & flag & info ["type-lhs"] ~doc)

let explicit_import =
  let doc =
    "For compliance with the Dedukti standard, the require directive should be \
     mandatory. However, this was not the case in the past. Because many \
     Dedukti files used the former, by default implicit imports are allowed \
     but this aim to be changed in the future."
  in
  Arg.(value & flag & info ["explicit-import"] ~doc)

let standard_check =
  let doc =
    "This parameter is used to ensure development are compliant with the \
     Dedukti standard. This is not active by default but should be in the \
     future. For the moment, this parameter is an alias for 'explicit-import' \
     option."
  in
  Arg.(value & flag & info ["standard"] ~doc)

let dkcheck config confluence de_bruijn export files eta ll sr_check
    errors_in_snf coc type_lhs explicit_import standard_check =
  Config.init config;
  Pp.print_db_enabled := de_bruijn;
  Option.iter Confluence.set_cmd confluence;
  Env.check_ll := ll;
  Reduction.eta := eta;
  Env.check_arity := not eta;
  Srcheck.srfuel := sr_check;
  Env.errors_in_snf := errors_in_snf;
  Env.explicit_import := explicit_import || standard_check;
  Typing.coc := coc;
  Typing.fail_on_unsatisfiable_constraints := type_lhs;
  let open Processor in
  let hook_after env exn =
    match exn with
    | None ->
        if not (Config.quiet config) then Errors.success (Env.get_filename env);
        if export then Env.export env;
        Confluence.finalize ()
    | Some (env, lc, e) -> Env.fail_env_error env lc e
  in
  let hook =
    {before = (fun _ -> Confluence.initialize ()); after = hook_after}
  in
  let load_path = Config.load_path config in
  Processor.handle_files ~hook ~load_path ~files TypeChecker;
  let f m =
    let input = Parsers.Parser.input_from_stdin (Basic.mk_mident m) in
    Processor.handle_input ~load_path ~input TypeChecker
  in
  Option.iter f config.Config.run_on_stdin

let cmd_t =
  Term.(
    const dkcheck $ Config.t $ confluence $ de_bruijn $ export $ files $ eta
    $ ll $ sr_check $ errors_in_snf $ coc $ type_lhs $ explicit_import
    $ standard_check)

let cmd =
  let doc = "Type check a list of Dedukti files" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Minimal proof checker for the lambdaPi calculus modulo rewriting. For \
         more information, see https://github.com/Deducteam/Dedukti.";
      `S Manpage.s_examples;
      `P "Given a Dedukti file $(i,examples/append.dk), the command";
      `Pre "dk check examples/append.dk";
      `P "should exit with 0 and output (on stderr)";
      `Pre "[SUCCESS] examples/append.dk was successfully checked.";
      (* TODO: exit status *)
      `S Manpage.s_bugs;
      `P "Report bugs to <dedukti-dev@inria.fr>.";
    ]
  in
  Cmd.v (Cmd.info "check" ~doc ~man) cmd_t
