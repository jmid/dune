(** Representation and parsing of Dune files *)

open Import

module Lint : sig
  type t = Preprocess.Without_instrumentation.t Preprocess.Per_module.t

  val no_lint : t
end

type for_ =
  | Executable
  | Library of Wrapped.t option

module Buildable : sig
  type t =
    { loc : Loc.t
    ; modules : Stanza_common.Modules_settings.t
    ; empty_module_interface_if_absent : bool
    ; libraries : Lib_dep.t list
    ; foreign_archives : (Loc.t * Foreign.Archive.t) list
    ; extra_objects : Foreign.Objects.t
    ; foreign_stubs : Foreign.Stubs.t list
    ; preprocess : Preprocess.With_instrumentation.t Preprocess.Per_module.t
    ; preprocessor_deps : Dep_conf.t list
    ; lint : Lint.t
    ; flags : Ocaml_flags.Spec.t
    ; js_of_ocaml : Js_of_ocaml.In_buildable.t
    ; allow_overlapping_dependencies : bool
    ; ctypes : Ctypes_field.t option
    }

  (** Check if the buildable has any foreign stubs or archives. *)
  val has_foreign : t -> bool

  (** Check if the buildable has any c++ foreign stubs. *)
  val has_foreign_cxx : t -> bool

  val has_mode_dependent_foreign_stubs : t -> bool
end

module Public_lib : sig
  type t

  (** Subdirectory inside the installation directory *)
  val sub_dir : t -> string option

  val loc : t -> Loc.t

  (** Full public name *)
  val name : t -> Lib_name.t

  (** Package it is part of *)
  val package : t -> Package.t

  val make
    :  allow_deprecated_names:bool
    -> Dune_project.t
    -> Loc.t * Lib_name.t
    -> (t, User_message.t) result
end

module Mode_conf : sig
  type t =
    | Byte
    | Native
    | Best (** [Native] if available and [Byte] if not *)

  val decode : t Dune_lang.Decoder.t
  val compare : t -> t -> Ordering.t
  val to_dyn : t -> Dyn.t

  module Kind : sig
    type t =
      | Inherited
      | Requested of Loc.t
  end

  module Map : sig
    type nonrec 'a t =
      { byte : 'a
      ; native : 'a
      ; best : 'a
      }
  end

  type mode_conf := t

  module Set : sig
    type nonrec t = Kind.t option Map.t

    val of_list : (mode_conf * Kind.t) list -> t
    val decode : t Dune_lang.Decoder.t

    module Details : sig
      type t = Kind.t option
    end

    val eval_detailed : t -> has_native:bool -> Details.t Mode.Dict.t
    val eval : t -> has_native:bool -> Mode.Dict.Set.t
  end

  module Lib : sig
    type t =
      | Ocaml of mode_conf
      | Melange

    val to_dyn : t -> Dyn.t

    module Map : sig
      type nonrec 'a t =
        { ocaml : 'a Map.t
        ; melange : 'a
        }
    end

    module Set : sig
      type mode_conf := t
      type nonrec t = Kind.t option Map.t

      val of_list : (mode_conf * Kind.t) list -> t
      val decode : t Dune_lang.Decoder.t

      module Details : sig
        type t = Kind.t option
      end

      val eval_detailed : t -> has_native:bool -> Details.t Lib_mode.Map.t
      val eval : t -> has_native:bool -> Lib_mode.Map.Set.t
    end
  end
end

module Library : sig
  type visibility =
    | Public of Public_lib.t
    | Private of Package.t option

  type t =
    { name : Loc.t * Lib_name.Local.t
    ; visibility : visibility
    ; synopsis : string option
    ; install_c_headers : (Loc.t * string) list
    ; public_headers : Loc.t * Dep_conf.t list
    ; ppx_runtime_libraries : (Loc.t * Lib_name.t) list
    ; modes : Mode_conf.Lib.Set.t
    ; kind : Lib_kind.t
        (* TODO: It may be worth remaming [c_library_flags] to
           [link_time_flags_for_c_compiler] and [library_flags] to
           [link_time_flags_for_ocaml_compiler], both here and in the Dune
           language, to make it easier to understand the purpose of various
           flags. Also we could add [c_library_flags] to [Foreign.Stubs.t]. *)
    ; library_flags : Ordered_set_lang.Unexpanded.t
    ; c_library_flags : Ordered_set_lang.Unexpanded.t
    ; virtual_deps : (Loc.t * Lib_name.t) list
    ; wrapped : Wrapped.t Lib_info.Inherited.t
    ; optional : bool
    ; buildable : Buildable.t
    ; dynlink : Dynlink_supported.t
    ; project : Dune_project.t
    ; sub_systems : Sub_system_info.t Sub_system_name.Map.t
    ; dune_version : Dune_lang.Syntax.Version.t
    ; virtual_modules : Ordered_set_lang.Unexpanded.t option
    ; implements : (Loc.t * Lib_name.t) option
    ; default_implementation : (Loc.t * Lib_name.t) option
    ; private_modules : Ordered_set_lang.Unexpanded.t option
    ; stdlib : Ocaml_stdlib.t option
    ; special_builtin_support : (Loc.t * Lib_info.Special_builtin_support.t) option
    ; enabled_if : Blang.t
    ; instrumentation_backend : (Loc.t * Lib_name.t) option
    ; melange_runtime_deps : Loc.t * Dep_conf.t list
    }

  include Stanza.S with type t := t

  val sub_dir : t -> string option
  val package : t -> Package.t option

  (** Check if the library has any foreign stubs or archives. *)
  val has_foreign : t -> bool

  (** Check if the library has any c++ foreign stubs. *)
  val has_foreign_cxx : t -> bool

  (** The foreign stubs archive. *)
  val stubs_archive : t -> Foreign.Archive.t option

  (** The list of foreign archives. *)
  val foreign_archives : t -> Foreign.Archive.t list

  (** The [lib*.a] files of all foreign archives, including foreign stubs. [dir]
      is the directory the library is declared in. Only files relevant to the
      [for_mode] selection will be returned. *)
  val foreign_lib_files
    :  t
    -> dir:Path.Build.t
    -> ext_lib:string
    -> for_mode:Mode.Select.t
    -> Path.Build.t list

  (** The path to a library archive. [dir] is the directory the library is
      declared in. *)
  val archive : t -> dir:Path.Build.t -> ext:string -> Path.Build.t

  val best_name : t -> Lib_name.t
  val is_virtual : t -> bool
  val is_impl : t -> bool
  val obj_dir : dir:Path.Build.t -> t -> Path.Build.t Obj_dir.t
  val main_module_name : t -> Lib_info.Main_module_name.t

  val to_lib_info
    :  t
    -> dir:Path.Build.t
    -> lib_config:Lib_config.t
    -> Lib_info.local Memo.t
end

module Executables : sig
  module Link_mode : sig
    type t =
      | Byte_complete
      | Other of
          { mode : Mode_conf.t
          ; kind : Binary_kind.t
          }

    include Dune_lang.Conv.S with type t := t

    val exe : t
    val object_ : t
    val shared_object : t
    val byte : t
    val native : t
    val js : t
    val compare : t -> t -> Ordering.t
    val to_dyn : t -> Dyn.t

    val extension
      :  t
      -> loc:Loc.t
      -> ext_obj:Filename.Extension.t
      -> ext_dll:Filename.Extension.t
      -> string

    module Map : Map.S with type key = t
  end

  type t =
    { names : (Loc.t * string) list
    ; link_flags : Link_flags.Spec.t
    ; link_deps : Dep_conf.t list
    ; modes : Loc.t Link_mode.Map.t
    ; optional : bool
    ; buildable : Buildable.t
    ; package : Package.t option
    ; promote : Rule.Promote.t option
    ; install_conf : Install_conf.t option
    ; embed_in_plugin_libraries : (Loc.t * Lib_name.t) list
    ; forbidden_libraries : (Loc.t * Lib_name.t) list
    ; bootstrap_info : string option
    ; enabled_if : Blang.t
    ; dune_version : Dune_lang.Syntax.Version.t
    }

  include Stanza.S with type t := t

  (** Check if the executables have any foreign stubs or archives. *)
  val has_foreign : t -> bool

  (** Check if the executables have any c++ foreign stubs. *)
  val has_foreign_cxx : t -> bool

  val obj_dir : t -> dir:Path.Build.t -> Path.Build.t Obj_dir.t
end

module Documentation : sig
  type t =
    { loc : Loc.t
    ; package : Package.t
    ; mld_files : Ordered_set_lang.t
    }

  include Stanza.S with type t := t
end

module Tests : sig
  type t =
    { exes : Executables.t
    ; locks : Locks.t
    ; package : Package.t option
    ; deps : Dep_conf.t Bindings.t
    ; enabled_if : Blang.t
    ; build_if : Blang.t
    ; action : Dune_lang.Action.t option
    }

  include Stanza.S with type t := t
end

module Include_subdirs : sig
  type qualification =
    | Unqualified
    | Qualified

  type t =
    | No
    | Include of qualification

  type stanza = Loc.t * t

  include Stanza.S with type t := stanza
end

(** The purpose of [Library_redirect] stanza is to create a redirection from an
    [old_name] to a [new_public_name].

    This is used in two cases:

    - When a library changes its public name, a redirection is created for
      backwards compatibility with the code using its old name.
      (deprecated_library_name stanza in dune files)

    - When hiding public libraries with [--only-packages] (or [-p]), we use this
      stanza to make sure that their project-local names remain in scope. *)
module Library_redirect : sig
  type 'old_name t = private
    { project : Dune_project.t
    ; loc : Loc.t
    ; old_name : 'old_name
    ; new_public_name : Loc.t * Lib_name.t
    }

  module Local : sig
    type nonrec t = (Loc.t * Lib_name.Local.t) t

    include Stanza.S with type t := t

    val of_private_lib : Library.t -> t option
  end
end

module Deprecated_library_name : sig
  module Old_name : sig
    type deprecation =
      | Not_deprecated
      | Deprecated of { deprecated_package : Package.Name.t }

    type t = Public_lib.t * deprecation
  end

  type t = Old_name.t Library_redirect.t

  include Stanza.S with type t := t

  val old_public_name : t -> Lib_name.t
end

val stanza_package : Stanza.t -> Package.t option

(** [of_ast project ast] is the list of [Stanza.t]s derived from decoding the
    [ast] according to the syntax given by [kind] in the context of the
    [project] *)
val of_ast : Dune_project.t -> Dune_lang.Ast.t -> Stanza.t list

(** A fully evaluated dune file *)
type t =
  { dir : Path.Source.t
  ; project : Dune_project.t
  ; stanzas : Stanza.t list
  }

val equal : t -> t -> bool
val hash : t -> int
val to_dyn : t -> Dyn.t

val parse
  :  Dune_lang.Ast.t list
  -> dir:Path.Source.t
  -> file:Path.Source.t option
  -> project:Dune_project.t
  -> t Memo.t

val fold_stanzas : t list -> init:'acc -> f:(t -> Stanza.t -> 'acc -> 'acc) -> 'acc

module Memo_fold : sig
  val fold_stanzas
    :  t list
    -> init:'acc
    -> f:(t -> Stanza.t -> 'acc -> 'acc Memo.t)
    -> 'acc Memo.t
end
