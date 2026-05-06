PS1='[\u@\h \W]\$ '

# Alias
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias l='ls -lah --color=auto'
alias rm='rm -iv'
alias cp='cp -iv'
alias mv='mv -iv'

# Activar bash-completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi

# Buscar en el historial por prefijo con flechas arriba/abajo
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# Autocompletado sin distinguir mayúsculas/minúsculas
bind 'set completion-ignore-case on'

# Historial persistente e ilimitado
HISTSIZE=-1                                         # Sin límite de comandos en memoria
HISTFILESIZE=-1                                     # Sin límite de líneas en el archivo .bash_history
HISTTIMEFORMAT="%F %T  "                            # Mostrar fecha y hora en el historial
shopt -s histappend                                 # Añadir, nunca sobreescribir
HISTCONTROL=ignoredups                              # Ignorar duplicados consecutivos
HISTFILE=~/.bash_history
export HISTFILE HISTSIZE HISTFILESIZE
PROMPT_COMMAND='history -a; history -c; history -r' # Guardar cada comando al instante
