{
  enable = true;

  extensions = [
    "Ansible"
    "C#"
    "Catppuccin"
    "Catpuccin Icons"
    "Context7 MCP Server"
    "CSV"
    "Dockerfile"
    "HTML"
    "Nix"
    "R"
    "Ruff"
    "TOML"
  ];

  userSettings = {
    autosave = "on_focus_change";
    base_keymap = "Emacs";
    buffer_font_family = "Fira Code";
    buffer_font_size = 14;
    ensure_final_newline_on_save = true;
    env.EDITOR = "zeditor --wait";
    file_types.Markdown = [ "*.md" "*.Rmd" "*.qmd" ];
    format_on_save = "on";
    hard_tabs = true;
    icon_theme.mode = "system";
    icon_theme.light = "Catppuccin Latte";
    icon_theme.dark = "Catppuccin Mocha";
    restore_on_startup = "last_workspace";
    show_whitespaces = "boundary";
    soft_wrap = "editor_width";
    tab_size = 4;
    theme.mode = "system";
    theme.light = "Catppuccin Latte";
    theme.dark = "Catppuccin Mocha";
    ui_font_size = 16;
  };
}
