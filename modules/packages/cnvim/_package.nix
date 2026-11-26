{
  symlinkJoin,
  neovim-unwrapped,
  makeWrapper,
  runCommandLocal,
  vimPlugins,
  lib,

  alduin,

  lua-language-server,
  nixd,
  ty,
  ruff,
  bash-language-server,
  jdt-language-server,
  typescript-language-server,

  universal-ctags,
  ripgrep,
  fd,
  sqlite,

  lazygit,
  ghostscript,
  mermaid-cli,
  tectonic,
  git-url,
}:
let
  packageName = "cnvim";

  runtimeDeps = [
    lua-language-server
    nixd
    ty
    ruff
    bash-language-server
    jdt-language-server
    typescript-language-server
    universal-ctags
    ripgrep
    fd
    sqlite
    lazygit
    ghostscript
    mermaid-cli
    tectonic
    git-url
  ];

  startPlugins = with vimPlugins; [
    alduin
    blink-cmp
    blink-compat
    comment-nvim
    vim-fugitive
    gitsigns-nvim
    inc-rename-nvim
    indent-blankline-nvim
    luasnip
    no-neck-pain-nvim
    nvim-lspconfig
    nvim-jdtls
    nvim-treesitter.withAllGrammars
    nvim-web-devicons
    oil-nvim
    project-nvim
    smartyank-nvim
    smear-cursor-nvim
    snacks-nvim
    statuscol-nvim
    trouble-nvim
    vim-illuminate
    vim-python-pep8-indent
    zellij-nav-nvim
  ];

  foldPlugins =
    let
      go =
        seen:
        builtins.foldl' (
          acc: next:
          if builtins.elem next acc then
            acc
          else
            acc ++ [ next ] ++ (go (seen ++ [ next ]) (next.dependencies or [ ]))
        ) seen;
    in
    go [ ];

  startPluginsWithDeps = lib.unique (foldPlugins startPlugins);

  grammarSplit = lib.partition (
    plugin: plugin.isTreesitterGrammar or false || plugin.isTreesitterQuery or false
  ) startPluginsWithDeps;

  # A start directory per language slows every runtime file search.
  grammars = symlinkJoin {
    name = "nvim-treesitter-grammars";
    paths = grammarSplit.right;
  };

  packpath = runCommandLocal "packpath" { } ''
    mkdir -p $out/pack/${packageName}/{start,opt}

    ${lib.concatMapStringsSep "\n" (
      plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}"
    ) (grammarSplit.wrong ++ [ grammars ])}

    cp -r ${./lua} $out/lua
    cp -r ${./snippets} $out/snippets
    cp -r ${./lspconfigs} $out/lspconfigs
    cp ${./init.lua} $out/init.lua
  '';
in
symlinkJoin {
  name = packageName;
  paths = [ neovim-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/nvim \
      --add-flags '-u' \
      --add-flags '${packpath}/init.lua' \
      --add-flags '--cmd' \
      --add-flags "'set packpath^=${packpath} | set runtimepath^=${packpath}'" \
      --set-default NVIM_APPNAME ${packageName} \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  passthru = {
    inherit packpath;
  };
}
