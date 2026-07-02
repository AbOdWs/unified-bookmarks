#!/bin/bash
# idea-watcher.sh — scans raw/ideas/ for new .md files, triggers فقيه for each one.
# Run via cron: */5 * * * * /root/idea-watcher.sh
# فقيه reads the idea, cross-references wiki/, and delivers a plan to Telegram with action buttons.

IDEAS=/root/knowledge/raw/ideas
PROCESSED=$IDEAS/processed
LOCK=/root/.faqih-idea.lock
LOG=/root/faqih.log

mkdir -p "$PROCESSED"

# Skip if فقيه is already running for an idea
if [ -f "$LOCK" ]; then
    PID=$(cat "$LOCK" 2>/dev/null)
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$LOCK"
fi

for f in "$IDEAS"/*.md; do
    [ -e "$f" ] || continue  # no files

    name=$(basename "$f" .md)
    echo "$(date -u +%FT%TZ) idea-watcher: queuing idea: $name" >> "$LOG"

    # Write the idea content as the faqih request
    cp "$f" /root/.faqih-idea-file.txt
    cat "$f" > /root/.faqih-request.txt

    # Lock and run فقيه in idea mode, then release lock
    bash /root/faqih-spec.sh idea &
    echo $! > "$LOCK"
    wait $!
    rm -f "$LOCK"

    # Move processed file out of the inbox
    mv "$f" "$PROCESSED/${name}-$(date +%s).md"

    echo "$(date -u +%FT%TZ) idea-watcher: done: $name" >> "$LOG"
done
