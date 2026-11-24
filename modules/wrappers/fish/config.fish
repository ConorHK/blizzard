# Read by every fish the wrapper starts, through --init-command.

set -gx PAGER "bat --plain"
set -gx MANPAGER "bat --plain"
set -gx FZF_CTRL_T_OPTS "--preview 'head {}'"
set -gx FZF_CTRL_R_OPTS --sort
set -gx LESSHISTFILE "$XDG_CACHE_HOME/less/history"

status is-interactive; or return

function fish_greeting
end

alias cat "bat --style='plain,rule,header' --paging never"
alias less "bat --plain"
alias df duf
alias du dust
alias wget 'wget --hsts-file=$XDG_DATA_HOME/wget-hsts'

alias gs "git status"
alias gc "git commit"
alias ga "git add"
alias gaa "git add --all"
alias gp "git push"
alias gl "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
alias gd "git -c diff.external=difft diff"
alias grc "git -c diff.external=difft show --ext-diff"

alias ls "@eza@ --hyperlink=auto --group --icons --git --header --all"
alias l "@eza@ --hyperlink=auto --group --icons --git --header --all --long"
alias lt "@eza@ --hyperlink=auto --group --icons --git --header --all --tree"
alias tree "@eza@ --hyperlink=auto --group --icons --git --header --all --tree"
alias la "eza -a"
alias ll "eza -l"
alias lla "eza -la"

# puffer-fish: !! and !$ expand as they do in bash.
set fish_function_path $fish_function_path[1] @puffer@/functions $fish_function_path[2..-1]
for file in @puffer@/conf.d/*.fish
    source $file
end

source @fzf@/share/fzf/key-bindings.fish
source @fzf@/share/fzf/completion.fish

    # vim mode
    fish_vi_key_bindings
    set fish_cursor_default     block      blink
    set fish_cursor_insert      line       blink
    set fish_cursor_replace_one underscore blink
    set fish_cursor_visual      block

    # Alduin-based fish colors
    set fish_color_normal dfdfaf
    set fish_color_command 87875f        # green
    set fish_color_param dfdfaf          # fg
    set fish_color_error 8b5f61          # red
    set fish_color_comment 878787        # cyan
    set fish_color_quote fed975          # yellow
    set fish_color_redirection dfdfaf    # fg
    set fish_color_end 878787            # cyan/soft
    set fish_color_operator 87afaf       # blue
    set fish_color_escape af875f         # orange-ish accent
    set fish_color_autosuggestion 626262 # dim gray to fit bg
    set fish_color_selection 262626      # black_soft
    set fish_color_search_match d69f74   # orange
    set fish_color_valid_path 87afaf     # blue
    set fish_color_cwd 87875f            # green
    set fish_color_user dfdfaf           # fg
    set fish_color_host 87afaf           # blue
    set fish_color_host_remote af8787    # magenta
    set fish_color_cancel 8b5f61         # red

@zoxide@ init fish | source
@nixYourShell@ fish | source

function __fish_command_not_found_handler --on-event fish_command_not_found
    @commandNotFound@ $argv
end

@carapace@ _carapace fish | source

# jj prompt in jj repos, git prompt elsewhere
function __starship_pick --on-variable PWD
    if jj root >/dev/null 2>&1
        set -gx STARSHIP_CONFIG @starshipConfig@/starship-jj.toml
    else
        set -gx STARSHIP_CONFIG @starshipConfig@/starship.toml
    end
end
__starship_pick

if test "$TERM" != dumb
    @starship@ init fish | source
end
