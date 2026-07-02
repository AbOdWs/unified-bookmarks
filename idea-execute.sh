#!/bin/bash
# idea-execute.sh — authorised wrapper for وكيل triggered by Telegram approve button.
# WAKIL_CONFIRM=1 is set deliberately here — this IS the human approval gate,
# exercised via the Telegram button press.
export WAKIL_CONFIRM=1
exec /root/wakil-run.sh "$@"
