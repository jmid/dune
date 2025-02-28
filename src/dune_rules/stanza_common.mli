open Import
open Dune_lang.Decoder

module Pkg : sig
  val decode : Package.t t
  val resolve : Dune_project.t -> Package.Name.t -> (Package.t, User_message.t) Result.t
  val field : stanza:string -> Package.t fields_parser
  val field_opt : ?check:unit t -> unit -> Package.t option fields_parser
  val default_exn : loc:Loc.t -> Dune_project.t -> string -> Package.t
end

(** [preprocess] and [preprocessor_deps] fields *)
val preprocess_fields
  : (Preprocess.Without_instrumentation.t Preprocess.Per_module.t * Dep_conf.t list)
      fields_parser

(** [instrumentation] multi field *)
val instrumentation
  : (Loc.t * (((Loc.t * Lib_name.t) * String_with_vars.t list) * Dep_conf.t list) list)
      fields_parser

module Modules_settings : sig
  type t =
    { root_module : (Loc.t * Module_name.t) option
    ; modules_without_implementation : Ordered_set_lang.Unexpanded.t
    ; modules : Ordered_set_lang.Unexpanded.t
    }

  val since_expanded : Syntax.Version.t
  val decode : t Dune_lang.Decoder.fields_parser
end
