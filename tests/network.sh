#!/usr/bin/env bash
# Both PATH and exported functions block real curl, including rebuilt PATHs.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\nexit 7\n' > "$HOME/.local/bin/curl"
chmod +x "$HOME/.local/bin/curl"
curl() { return 7; }
export -f curl
