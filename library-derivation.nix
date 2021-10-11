{ nixlib, mkDerivation, fstar-dependencies, findutils }:
let
  mk = lib: let
    plugin-entrypoints = lib.plugin-entrypoints or [];
    bash-list-of = l: nixlib.concatMapStringsSep " " (x: nixlib.escapeShellArg "${x}") l;
  in mkDerivation {
    name = "${lib.name}-lib";
    phases = [ "buildPhase" "installPhase" ];
    buildInputs = [findutils] ++ fstar-dependencies;
    buildPhase = ''
      mkdir modules plugins
      touch plugin-modules
      for dependency in ${bash-list-of (map mk lib.dependencies)}; do
         find "$dependency/modules/" \( -type f -or -type l \) -exec ln -fs '{}' ./modules/ \;
         find "$dependency/plugins/" \( -type f -or -type l \) -exec ln -fs '{}' ./plugins/ \;
         cat "$dependency/plugin-modules" >> plugin-modules
      done
      ${
        nixlib.concatMapStringsSep "\n" (path:
          ''ln -s ${path} ./modules/${nixlib.escapeShellArg (builtins.baseNameOf path)}''
        ) lib.modules
      }
      for filename in ${bash-list-of (map builtins.baseNameOf lib.plugin-entrypoints)}; do
         modulename="''${filename%.*}"
         echo "$modulename" >> plugin-modules
         ocamlname="''${modulename//./_}"
         cmxsname="$ocamlname.cmxs"
         mkdir out
         echo "########## C"
         fstar.exe --include ./modules/ \
                   $(find ./plugins/ \( -type f -or -type l \) -printf "--load_cmxs %P ") \
                   --extract "* -FStar" --odir out --codegen Plugin "$filename"
         echo "########## D"
         find ./modules/ \( -type f -or -type l \) \( -name '*.ml' -or -name '*.ml' \) \
              -printf '%P\0' | while IFS= read -r -d ''' f; do
              rm -r "./out/$f"
              ln -s "./modules/$f" "./out/$f"
         done
         echo "########## E"
         cd out
         ocamlbuild -use-ocamlfind -cflag -g -package fstar-tactics-lib "$cmxsname"
         cp "_build/$cmxsname" "../plugins/$cmxsname"
         cd ..
         rm -rf out
      done
    '';
    installPhase = ''
      mkdir $out
      mv plugin-modules $out/plugin-modules
      mv modules $out/modules
      mv plugins $out/plugins
    '';
  };
in mk
