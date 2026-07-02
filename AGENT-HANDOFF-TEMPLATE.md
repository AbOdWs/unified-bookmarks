<!--
==============================================================================
AGENT HANDOFF BRIEF  —  fill this when you finish working on a project.
Purpose: a DIFFERENT agent (or you, months later) must become productive on
this project in ~5 minutes and WITHOUT breaking anything in production.

HOW TO FILL (instructions to the agent completing this doc):
- Write for a capable agent who has NEVER seen this project. Assume zero context.
- Prefer exact commands, paths, and file names over prose. Show, don't describe.
- Surface TACIT knowledge: anything true about the running system that is NOT
  obvious from reading the repo. This is the whole point of the document.
- The single most valuable section is "THE MAP (repo vs runtime)". Spend effort there.
- NEVER paste secret values (tokens, keys, passwords). Name the secret and say
  where it lives (e.g. "Groq key -> /root/config.json:groq_api_key").
- If something is unknown, write "UNKNOWN" — do not guess. Guesses are worse than gaps.
- Delete these HTML comments? No — leave them; they guide the next fill.
- Keep each section tight. A long brief that's skimmed beats an exhaustive one that isn't.
==============================================================================
-->

# <PROJECT NAME> — Agent Handoff Brief

- **Status:** <shipped | testflight | in-dev | dormant | paused>
- **Last worked:** <YYYY-MM-DD> by <which agent/model, e.g. Claude Opus 4.8>
- **Repo:** <url or "no repo — runtime only">
- **Repo visibility:** <public | private>  <!-- decides what may be committed -->
- **One line:** <what it is and who it's for>

---

## 1. TL;DR — read this first
<!-- 3-6 sentences. What the project does, its current real state, and what a new
     agent is most likely being asked to do next. If you read only this, you should
     not do anything dangerous by accident. -->
<...>

## 2. THE MAP — repo vs runtime  ⭐ MOST IMPORTANT
<!-- The #1 cause of wasted time and broken prod: assuming "the repo == the system".
     Make the real topology explicit. Answer ALL of these: -->

- **Source of truth:** <where the canonical code lives — repo? which branch?>
- **Where it actually runs:** <VPS/host, container name, service manager, ports>
- **Deploy path (edit → live):** <exact steps. e.g. "edit in repo → cp to /root/ →
  `systemctl restart X`" or "import JSON in n8n UI">
- **Files that exist ONLY at runtime and are NOT in the repo** (critical — list every one):
  <!-- e.g. /root/config.json, /root/.some-token, AIOS/skills/*.md referenced by a
       script but never committed, n8n workflow state, a database, cron entries. -->
  - `<path>` — <what it is, why it matters, how to recreate it>
- **Repos this project spans** (if more than one — e.g. code repo vs data/vault repo):
  - `<repo>` — <what lives here>
- **What is committed vs what must NEVER be committed** (esp. if repo is public):
  - Never commit: <secrets, personal data, vault content, ...>

## 3. How to run / reproduce
<!-- Exact commands to run it locally or observe it running. Include how to see logs. -->
- Run: `<...>`
- Logs: `<path or command>`
- Health check: `<how to tell it's alive>`

## 4. Architecture & data flow
<!-- Components and how a request/event moves through them. A text diagram is great. -->
```
<component A> → <component B> → <storage> → <output>
```
<...>

## 5. Tech stack & external services
<!-- Every external dependency, what it's used for, and WHERE its credential lives
     (name the config key/path, never the value). Note free-tier limits / quotas. -->
| Service | Used for | Credential location | Notes / limits |
|---------|----------|---------------------|----------------|
| <e.g. Groq> | <LLM> | `<path:key>` | <free tier?> |

## 6. Configuration & state
<!-- Config keys the project reads and what each does. Where persistent state lives. -->
- Config file: `<path>` — keys: <list each key + purpose>
- State/data: <files, DB, folders — what holds the mutable state>

## 7. Agents / personas  (if this project uses AI agents)
<!-- If the project has its own agents, document each: role, model tier, hard limits,
     and where its "soul"/system-prompt file lives. Embed the soul files or link them.
     If an agent is dormant (built but not live), say so loudly and say what gates it. -->
- **<agent name>** — role: <...> · model: <...> · lives: `<path>` · status: <live|dormant>
  - Hard limits: <what it must never do>
<!-- Repeat per agent. Paste or link the actual soul/prompt files if short. -->

## 8. Safety rails — things that can break production  ⭐
<!-- Be blunt. What a careless change would destroy, and the guardrails that exist.
     Commands that are destructive. Approval gates. "Never touch X while it's live." -->
- <e.g. "Never push to main — it auto-deploys.">
- <e.g. "Service Y requires WAKIL_CONFIRM=1; the gate is human-only, never automate it.">

## 9. Gotchas & hard-won lessons
<!-- Non-obvious bugs, constraints, and surprises ALREADY discovered. Each one you
     record here saves the next agent from rediscovering it the hard way. -->
- <e.g. "Telegram inline-button url only allows http(s)/tg:// — obsidian:// drops the msg.">
- <e.g. "Groq blocks the python-urllib User-Agent (403); send curl/8.0.">
- <e.g. "callback_data is capped at 64 bytes; Arabic slugs are multi-byte and overflow.">

## 10. Known issues & roadmap
- Known issues: <...>
- Next / planned: <...>
- Explicitly out of scope: <...>

## 11. Glossary & domain terms
<!-- Project-specific names, especially non-English ones, so a new agent isn't lost. -->
- **<term>** — <meaning>

## 12. Open questions for the human
<!-- Things the next agent should ASK before acting, not assume. This is where you
     put the "interesting questions" — the decisions only the owner can make, or
     facts you couldn't verify (like whether the live config matches the repo). -->
- <...>
