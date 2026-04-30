# ~/.bashrc

# Colores en ls y grep
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Prompt con colores: usuario@host:directorio$
PS1='\[\e[0;32m\]\u@\h\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]\$ '

# Alias útiles
alias rm='rm -iv'
alias cp='cp -iv'
alias mv='mv -iv'
alias l='ls -lah --color=auto'

# Bash-completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi

# Buscar en el historial con flechas arriba/abajo
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# Autocompletado sin distinguir mayúsculas/minúsculas
bind 'set completion-ignore-case on'

# Historial persistente e ilimitado
HISTSIZE=-1
HISTFILESIZE=-1
HISTTIMEFORMAT="%F %T  "
shopt -s histappend
HISTCONTROL=ignoredups
HISTFILE=~/.bash_history
export HISTFILE HISTSIZE HISTFILESIZE
PROMPT_COMMAND='history -a; history -c; history -r'
