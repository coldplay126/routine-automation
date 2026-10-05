#!/bin/bash
# macOS sets the read-only, transient PENDIN bit on raw -> canonical transitions.
# Compare every configurable flag/control character, not that kernel queue marker.
state=$(stty -g)
lflag=${state#*:lflag=}; lflag=${lflag%%:*}
printf '%s:lflag=%x:%s\n' "${state%%:lflag=*}" "$((16#$lflag & ~0x20000000))" "${state#*:lflag=$lflag:}"
