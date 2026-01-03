#!/usr/bin/env bash

SESSION="rag-dev"

# Check if session exists
tmux has-session -t $SESSION 2>/dev/null

if [ $? != 0 ]; then
  # Create new session with default shell (Postgres + Zsh) - keep this as main command
  tmux new-session -d -s $SESSION -n "db-shell" "nix develop"

  # Create window for Backend
  tmux new-window -t $SESSION -n "backend" "nix develop .#backend"

  # Create window for Frontend
  tmux new-window -t $SESSION -n "frontend" "nix develop .#frontend"

  # Select first window
  tmux select-window -t $SESSION:0
fi

# Attach to session
tmux attach-session -t $SESSION
