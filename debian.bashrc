PS1="(\[\033[01;34m\]\t\[\033[0m\])\[\033[38;5;10m\]\u\[\033[0m\]@\[\033[38;5;10m\]\h\[\033[0m\]:[\[\033[38;5;1m\]\w\[\033[0m\]]\$"

if [ -f ~/.venv/bin/activate ]; then
  . ~/.venv/bin/activate
fi

if [ -t 0 ]; then
  fastfetch
  tabs 4
fi
