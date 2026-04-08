---
title: Architecture Docs, README, and GitHub-Readiness Pass
type: docs
status: completed
date: 2026-04-08
---

# Architecture Docs, README, and GitHub-Readiness Pass

## Enhancement Summary

**Deepened on:** 2026-04-08
**Research agents run:** best-practices-researcher, framework-docs-researcher, spec-flow-analyzer, code-simplicity-reviewer (4 parallel agents).

### Scope cuts applied (from simplicity + best-practices review)

The original v1 proposed a 10-file architecture suite, a `.github/` scaffold, a CI workflow, a credits-audit phase, and 4 Mermaid sequence diagrams. Two independent reviewers converged on "too much for a solo hobby project." Cuts applied directly:

1. **Architecture suite 10 → 5 files.** Merged autoloads+signals, entities+components, resources+vfx. Dropped standalone `10-adr-index.md` (the `docs/decisions/` folder filenames already ARE an index — a one-paragraph "ADR map" lives in `docs/architecture/README.md` instead). Dropped standalone `09-adding-things.md` cookbook — solo-dev recipes for a codebase you just wrote is guaranteed rot. Dropped standalone `08-water-and-vfx.md` — [docs/pixel-water-shader-reference.md](../pixel-water-shader-reference.md) already exists; a second doc that "links heavily" to it is a redirect.
2. **Mermaid diagrams 4 → 3.** Kept: scene-tree flowchart, Ship FSM stateDiagram-v2, one player-damage sequenceDiagram. Dropped: wave-clear, water-impact, explosion-pipeline sequence traces — they are copy-paste exercises of the first one and teach nothing new.
3. **`.github/` scaffold cut.** Issue/PR templates for a solo repo with zero external contributors are LARP. Added the day the first external issue lands.
4. **Test-CI workflow deferred; deploy-CI for Pages added (v3).** Decision made, not a gate. The *test* CI (gdformat/gdlint/gut) remains deferred because you run those locally per CLAUDE.md and a red test-badge on first push is worse than no badge — ready-to-paste YAML lives in Appendix B. The *deploy* CI for GitHub Pages is **newly in scope in v3**: this project's export preset has `variant/thread_support=false`, which sidesteps the COOP/COEP requirement that usually blocks Godot 4 on Pages, so plain static hosting works. Deploy workflow lives in Appendix D.
5. **Asset credits inventory cut as a phase.** Reduced to one-line conditional in Phase 3: "if you used third-party assets, add `assets/CREDITS.md`." 30 seconds of recall, not a walking-the-tree audit.
6. **Open Questions 1/2/3/4/5 resolved inline, not asked.** License=MIT, CI=deferred, `.vscode/`=ignored, visibility=private-first, screenshot=placeholder-first-then-real. Only one real question remains (hero GIF timing).

### Phase 0 pre-flight added (from spec-flow review)

The original plan opened straight into writing docs. The spec-flow reviewer flagged three ordering bugs: pre-existing dirty tree, screenshot timing (should be early so bad visuals don't invalidate prose), and no runnable smoke test. Phase 0 now consolidates pre-flight: clean tree, ADR audit, hygiene grep, smoke run, screenshot capture (or placeholder commit). Phase 3 Step A (hygiene grep) moved up into Phase 0; Phase 3 Step C (credits) collapsed to one line.

### Phase 1.5 dogfood step added

The entire deliverable is an onboarding suite but had zero validation. Added: a 15-minute cold-reader test (user reads 01→03, answers 3 seed questions, fix gaps that surface). Cheap, high-signal, the only verification that the suite works.

### Doc-rot mitigations revised

Best-practices reviewer pushed back on line-range anchors. Revised strategy: **function-name anchors > line-range anchors**. Added `<!-- verified against commit <sha> on <date> -->` stamps at the top of each architecture file + a one-screen `docs/architecture/VERIFY.md` manual recheck list. Dropped the "line ranges" mitigation.

### `.gitignore` concrete patch provided

Framework-docs reviewer noted that GitHub's official `Godot.gitignore` is stale (targets Godot 3). Current project `.gitignore` is close-to-correct but missing `export_credentials.cfg` (real footgun), `/builds/`, `Thumbs.db`, `*.swp`, `*~`. Full ready-to-paste version in Appendix A.

### Key decisions locked

| Decision          | Locked to                  | Source                       |
|-------------------|----------------------------|------------------------------|
| License           | **MIT**                    | framework-docs (Godot convention, asset+code simple) |
| Test-CI           | **Deferred**               | simplicity + CI-red-on-first-push risk |
| Deploy-CI (Pages) | **Shipped (v3)**           | `thread_support=false` unblocks Pages hosting |
| `.github/` scaffold | **Not now**              | simplicity (LARP for solo)   |
| Arch suite shape  | **5 files, ~900 lines**    | best-practices (matklad pattern) + simplicity |
| Diagrams          | **3 total (scene, FSM, 1 signal)** | simplicity                 |
| Cookbook          | **Cut entirely**           | simplicity                   |
| ADR index doc     | **Cut; paragraph in arch README** | both reviewers           |
| Repo visibility   | **Private-first, flip after user skim** | (default)          |
| `.vscode/`        | **Ignored**                | (default)                    |
| Screenshot        | **Placeholder committed Phase 0; real capture before visibility flip** | spec-flow |

### New considerations discovered

- **`.gd.uid` sidecars MUST remain committed** — ADR 010 §6 already, but framework-docs reviewer confirmed against Godot 4.4+ docs. The current `.gitignore`'s *omission* of `*.uid` is correct by design.
- **GitHub Pages CAN host this project's Web export cleanly** — the plan's v2 claim (COOP/COEP headers required) is **wrong for this specific project** because [export_presets.cfg](../../export_presets.cfg) has `variant/thread_support=false`. No threading → no `SharedArrayBuffer` → no cross-origin-isolation headers required → plain static hosting works. Pages is now the target host, not itch.io. A **deploy workflow** (separate from the deferred test-CI workflow) is added to Phase 3. See Appendix D.
- **gdtoolkit 4.x is the Godot-4 branch** (`pip install "gdtoolkit==4.*"`). Documented for future CI and for the README dev setup section.
- **`--import || true` is the standard CI trick** for Godot headless first-run (non-zero exit on import warnings is normal). Captured in Appendix B for future reference.
- **ADR staleness propagation risk** — the component refactor just landed (`07d36d6`); some ADRs predate it. An ADR audit is part of Phase 0 Step 4, not assumed.

### What stayed the same

The core three deliverables (README, architecture suite, GitHub sweep), the overall phase structure, the "link don't duplicate" doctrine, and the Mermaid-only diagram rule. The plan got *smaller*, not redirected.

---

## Overview

The component-architecture refactor ([docs/plans/2026-04-07-refactor-component-architecture-plan.md](2026-04-07-refactor-component-architecture-plan.md)) has landed on `main` (commit `07d36d6`). The repo is now internally coherent — 14 ADRs, 40 GUT tests, feature-folder layout — but it has **no README.md**, no onboarding path for a new human contributor, and no LICENSE. The only top-level prose is [CLAUDE.md](../../CLAUDE.md), which is written for *an AI agent who has already cloned the repo*, not for a stranger deciding whether to.

This plan produces three deliverables:

1. **`README.md`** — the public face of the repo. Game description, hero GIF (or placeholder), how to run, controls, feature highlights, tech stack, license.
2. **`docs/architecture/` onboarding suite (5 files)** — a curated tour of the codebase for the next human (or AI agent with no prior context) to read on day one. Anchored to ADRs but rewritten for onboarding, not for decision-record archaeology.
3. **GitHub-readiness sweep** — `.gitignore` audit, LICENSE, remove working-state artifacts, repo-hygiene grep, `gh repo edit` metadata, **Web export + GitHub Pages deploy workflow** (new: makes the game playable at `https://<user>.github.io/PirateShipGame/`).

Deliberately out of scope: rewriting CLAUDE.md, adding new ADRs, writing CONTRIBUTING.md, issue/PR templates, **test-CI workflow** (deploy-CI is in scope; test-CI is not), FUNDING.yml, CHANGELOG.md.

## Problem Statement / Motivation

**What's missing today**

- **No README.md** at repo root. GitHub landing page shows nothing. CLAUDE.md is not a substitute; its audience is an agent with full repo access, not a browser.
- **No onboarding tour.** 14 ADRs exist but they're *decision records* — "why we chose X over Y" — not *"how does this codebase fit together"*. A new reader has to reverse-engineer the scene tree from [main/main.tscn](../../main/main.tscn) and cross-reference 8 feature folders.
- **No license.** Pushing to public GitHub without a LICENSE is ambiguous at best, a legal footgun at worst. Godot's MIT license covers the engine, not user code.
- **Working-state leakage risk.** [.gitignore](../../.gitignore) is close-to-correct but missing `export_credentials.cfg` and OS/editor noise.
- **No social-facing metadata.** No repo description, no hero media, no `gh repo edit` topics.

**Why now**

Architecture is in its most coherent state it will ever be before new features add drift. Documenting now locks in the mental model while the architect's context is fresh and gives the next session a faster runway.

## Proposed Solution

### Deliverable 1 — `README.md` (repo root)

A concise (**target 150-200 lines**, max 220) public-facing readme. Target reader: a Godot-literate developer browsing GitHub who has never seen the repo.

**Section order** (refined by best-practices research — hero media up front):

1. **Title + one-line pitch** — "A pixel-art top-down pirate ship arena game built in Godot 4.6."
2. **Hero media** — GIF preferred over static screenshot (ffmpeg → gifski pipeline, ≤8 MB, 480p, 3-5s loop). Placeholder screenshot accepted for first commit; real capture before visibility flip. Lives at `docs/media/hero.gif`.
3. **Play it in browser** — live link to the GitHub Pages build: `https://<user>.github.io/PirateShipGame/`. Populated after Phase 3 Step F's first successful deploy. No placeholder needed — the deploy workflow is part of this plan, so the URL is known.
4. **Features** — 6-bullet list (pixel water shader, composable components, wave progression, stylized explosions, sea mines, minimap). Each bullet links to its plan or ADR.
5. **Controls** — table pulled from [features/hud/controls_overlay.gd](../../features/hud/controls_overlay.gd) as ground truth.
6. **Running the game** — Godot 4.6.1, open in editor, F5. Headless-test command block.
7. **Tech stack** — Godot 4.6 / GDScript / Forward+ / 640×360 viewport @ 2× integer. Link [project.godot](../../project.godot).
8. **Project structure** — the 8-line tree (copied from CLAUDE.md).
9. **Architecture at a glance** — 4-line summary + link to `docs/architecture/README.md`.
10. **Development** — `gdformat`, `gdlint`, `gut` commands. Link to CLAUDE.md for the full convention list.
11. **License** — MIT.
12. **Credits** — inline if all self-made; link to `assets/CREDITS.md` if any third-party.

**Badges (3-4 max, skip entirely if they risk rotting):**
- Godot 4.6 shield
- License: MIT shield
- Last commit shield
- (No CI badge — CI is deferred.)

**What the README must NOT do**
- Duplicate CLAUDE.md verbatim.
- Include onboarding deep-dives (those live in `docs/architecture/`).
- Quote refactor-plan phase numbering — meaningless to outside readers.

### Deliverable 2 — `docs/architecture/` onboarding suite (5 files)

```
docs/architecture/
├── README.md                           ─ index, 15-min path, ADR map, VERIFY pointer
├── 01-overview.md                      ─ concept, Godot version, run loop, annotated scene tree
├── 02-autoloads-and-signals.md         ─ Events bus, GameState, AudioManager, KeybindsManager + signal flow
├── 03-entities-and-components.md       ─ Ship / EnemyShip / Cannonball / SeaMine + 10 components table + FSM
├── 04-resources-and-vfx.md             ─ ShipStats / WaveConfig / Resource doctrine + water pipeline pointer
└── VERIFY.md                           ─ one-screen manual recheck list
```

**Doctrine per file (carried forward from v1 + refined):**

- **Link, don't duplicate.** Every claim has a `file_path` markdown link. **Prefer function-name anchors over line-number anchors** (`Ship._on_hurtbox_hit` outlives any refactor that doesn't rename it). Use bare file links, not `#Lxx` ranges, except when a specific line is the whole point.
- **Diagrams via Mermaid.** Three total across the suite: scene-tree flowchart in 01, Ship FSM stateDiagram-v2 in 03, one player-damage sequenceDiagram in 02.
- **Mermaid conventions** (from best-practices research):
  - `flowchart TD` for structural trees; `[[Box]]` for autoloads, `subgraph` for feature folders, plain `[Box]` for nodes.
  - `sequenceDiagram` for signal flows; **`->>` for direct calls, `-->>` for signal emissions** (this visual distinction is the highest-value convention).
  - Cap participants at 6 (GitHub markdown column width).
  - No custom themes (breaks dark/light mode).
- **Last-verified stamps.** Each file opens with `<!-- verified against commit <sha> on <date> -->`. When a future refactor lands, `grep -rn "verified against" docs/architecture/` lists what to re-skim.
- **Code in docs is illustrative only.** Prefer quoting 5 real lines from the codebase over writing 20 example lines.
- **Per-file opening contract:** "What you'll know after reading this" (3-4 bullets) and closing "What to read next."
- **Whole suite readable in under an hour.** Target ~900 lines across 5 files, hard cap 1500.

**Per-document sketch:**

#### `README.md` (architecture index)
- "Read in this order" ordered list of the 4 content files.
- "If you only have 15 minutes" → read 01 + 03.
- ADR map paragraph: one sentence per ADR with "read this if you're about to…" triggers. Replaces the cut standalone `10-adr-index.md`.
- Cross-link to CLAUDE.md, VERIFY.md, refactor plan.

#### `01-overview.md` (merges v1's 01 + 02)
- Game concept in 3 sentences.
- Godot version / render pipeline / viewport-stretch strategy (link [project.godot](../../project.godot)).
- **Run loop** — prose + Mermaid sequence: "Godot loads main.tscn → main.gd wires services → WaveDirector drives progression → Ship lives until HP=0."
- **Annotated scene tree** — ASCII tree of [main/main.tscn](../../main/main.tscn) with each node's role. Table form: node → script → owns → emits.
- Why main.gd is thin (quote ADR 010 + [main/main.gd](../../main/main.gd)).

#### `02-autoloads-and-signals.md` (merges v1's 03 + 06)
- **Per-autoload section:**
  - Events ([autoload/events.gd](../../autoload/events.gd)) — signal bus, discipline rules from ADR 007, signal inventory grouped (Combat / Waves / VFX / Audio / Stats).
  - GameState ([autoload/game_state.gd](../../autoload/game_state.gd)) — RunStats owner, ADR 008 scope.
  - AudioManager ([autoload/audio_manager.gd](../../autoload/audio_manager.gd)) — ADR 011.
  - KeybindsManager ([autoload/keybinds_manager.gd](../../autoload/keybinds_manager.gd)) — ADR 012.
- Load order + "cross-autoload refs only inside `_ready()`" rule.
- **One end-to-end signal trace** (player takes cannonball damage) with Mermaid `sequenceDiagram`: Hurtbox.area_entered → Ship._on_hurtbox_hit → HealthComponent.apply_damage → Ship emits `died` → main.gd respawn. Uses `->>` / `-->>` convention.

#### `03-entities-and-components.md` (merges v1's 04 + 05)
- **Entity section:** Ship, EnemyShip, Cannonball, SeaMine. Each gets scene link, root script, one-line purpose, component list.
- **Ship FSM** — Mermaid `stateDiagram-v2` of `NORMAL / DASHING / INVINCIBLE / DEAD`.
- **Entity-vs-Component boundary line:** entity owns FSM + bus dispatch; components own one verb and emit upward.
- **Component table** — the 10 ship components under [features/ship/components/](../../features/ship/components/). Columns: name | file | one-verb role | listens to | emits | tick mode (process/physics/signal-only).
- **Default-OFF rule** + Node-vs-Node2D rule (ADR 010 §7) with HurtboxComponent as current carve-out.

#### `04-resources-and-vfx.md` (merges v1's 07 + 08)
- Resource catalog: ShipStats, ShipConfig, DashStats, WeaponConfig, WaveConfig, WaveSet, ExplosionStats, WaterTuning. File links.
- Resource doctrine (ADR 009) summarized in onboarding voice — three hazards (field writes, shared-material uniform writes, Curve/Gradient mutation).
- Hot-reload rules: which components re-read per frame, which cache at setup.
- **Water pipeline** — 1-paragraph overview + link to [docs/pixel-water-shader-reference.md](../pixel-water-shader-reference.md) as the canonical deep dive. DO NOT duplicate shader internals.
- **Explosion atlases** — 1-paragraph pointer to [features/vfx/explosion_stats.tres](../../features/vfx/explosion_stats.tres) and the sprite-vs-3D toggle.

#### `VERIFY.md`
- 10-minute manual recheck pass to run after any structural refactor.
- Format: one-line assertions with file links. Example: "✅ main.gd still has `_on_ship_respawned` calling camera snap", "✅ Events bus still groups signals under Combat/Waves/VFX/Audio/Stats", "✅ 10 components in features/ship/components/ match the 03-entities table".
- Target: 15-20 assertions, under 1 screen.

### Deliverable 3 — GitHub-readiness sweep

**Phase 0 absorbs most of the old Phase 3 hygiene work.** Phase 3 is now thin.

#### 3a. `.gitignore` audit

Current [.gitignore](../../.gitignore) is close-to-correct but missing editor-state and the `export_credentials.cfg` footgun. Full replacement in **Appendix A**. Commit: `chore(gitignore): audit pre-publication`.

#### 3b. LICENSE

**MIT** (decided, not a question). Matches Godot engine, covers code + assets, zero compliance friction for a solo project. File at repo root: `LICENSE`. Copyright "(c) 2026 Alan". Update README license section to match. Commit: `chore: add LICENSE (MIT)`.

#### 3c. Asset credits (conditional, one-line)

If any asset under [assets/](../../assets/) or `features/*/textures/` is third-party, add `assets/CREDITS.md` with per-file attribution. If all self-made, note "all assets self-made" in README Credits section. **Not a phase; 30 seconds of recall.**

#### 3d. Web export + GitHub Pages deploy (NEW in v3)

Ship the game as a playable browser build at `https://<user>.github.io/PirateShipGame/`. Three substeps:

1. **Export preset tweak.** Change [export_presets.cfg](../../export_presets.cfg) `export_path` from `../PirateShipGameWeb/index.html` to `build/web/index.html` so the GitHub Actions runner writes inside the workspace. Confirm `variant/thread_support=false` (already correct — this is the reason Pages works at all; see Enhancement Summary note). Confirm `exclude_filter` still strips `addons/gut/*`, `addons/pirate_dev_tools/*`, `tests/*` (already correct).
2. **Deploy workflow.** Create `.github/workflows/deploy-pages.yml` with the contents of **Appendix D**. This workflow installs Godot 4.6.1 headless, caches the `.godot/` import folder, runs the Web export, adds a `.nojekyll` marker, and publishes the output via `actions/deploy-pages@v4`.
3. **Enable Pages.** In repo Settings → Pages → Source: **"GitHub Actions"** (not "Deploy from a branch"). First deploy kicks off on next push to `main` or via workflow_dispatch. URL visible in the Actions job summary once green.

**Scope note.** This is a *deploy* workflow, not a *test* workflow. The test-CI (gdformat / gdlint / GUT) decision remains deferred — see Appendix B. The two workflows are independent; shipping one does not imply shipping the other.

#### 3e. Repo metadata (post-push, `gh repo edit`)

- Description: one-line pitch matching README.
- Topics: `godot`, `godot-4`, `gdscript`, `pixel-art`, `game`, `game-development`, `pirate`, `arcade`.
- **Homepage**: the Pages URL — `https://<user>.github.io/PirateShipGame/` — set after the first successful deploy.
- Social preview: same hero GIF/screenshot as README. Upload via GitHub web UI.

**Not a commit** — settings on the GitHub side.

#### Explicitly NOT in Phase 3

- `.github/` scaffold (issue templates, PR template, FUNDING, CODEOWNERS, SECURITY, CODE_OF_CONDUCT) — all premature for solo.
- **Test-CI workflow** — deferred. Appendix B has the ready-to-paste YAML for the day you change your mind. (Note: deploy-CI for Pages, Appendix D, IS in scope.)
- CONTRIBUTING.md — add when first external PR arrives.
- CHANGELOG.md — add on first tagged release.

## Technical Considerations

### Consistency with CLAUDE.md

CLAUDE.md is the *mutable* source of truth for agent conventions. The architecture tour must not contradict it and must not duplicate it verbatim. Rule: CLAUDE.md has the rules, architecture tour has the *explanations and examples*. Cross-link aggressively.

### Consistency with ADRs

ADRs are frozen — decisions at a point in time. The architecture tour describes current state. **ADR staleness audit happens in Phase 0 Step 4**, not assumed: the component refactor just landed and some ADRs may predate it; any stale claim gets a one-line errata in the architecture README's ADR map paragraph rather than being silently propagated into onboarding voice.

### Diagram format

Mermaid only. Flowchart + stateDiagram-v2 + sequenceDiagram are the three used types. No `mindmap`, `C4Context`, `timeline`, or `gitGraph`. No custom themes. Participants capped at 6 (GitHub column width). Call vs signal distinction via `->>` / `-->>`.

### Documentation lives in-repo

No external wiki. GitHub Wiki and external Notion pages detach from the commit graph and go stale. Everything in `docs/`.

### Link stability

Relative paths (`../../features/ship/ship.gd`), not absolute `res://` URIs. Function-name anchors in prose. Last-verified stamps at the top of each file.

### Doc-rot maintenance note (to embed in `docs/architecture/README.md`)

> If you refactor a function referenced by these docs, grep `docs/architecture/` for its name and fix anchors. After any structural refactor, run through `VERIFY.md` and update the last-verified stamp lines.

## System-Wide Impact

- **Signal chain**: None. Documentation change only.
- **Error propagation**: None.
- **State lifecycle risks**: None in code. Risk in docs: function-name anchors if a future refactor renames a function. Mitigated by `VERIFY.md` + last-verified stamps.
- **Scene interface parity**: None.
- **Integration test scenarios**: None. The doc validation is the dogfood step in Phase 1.5, not a code test.

## Acceptance Criteria

### Phase 0 pre-flight
- [x] `git status` clean on `main` (uncommitted rename of water-shader plan is resolved).
- [x] Game launches end-to-end via F5 with zero errors in the output panel.
- [x] Hygiene grep clean (no stray `print()`, no untriaged `FIXME`, no `handoff.md`/`scratch.md`/`notes.md` at repo root).
- [x] ADR audit complete: for ADRs 001–014, each marked "current / superseded / needs errata" in a scratch note; any "superseded" logged into the architecture README ADR map.
- [x] Hero media committed (real GIF or placeholder screenshot) at `docs/media/hero.gif` or `docs/media/hero.png`.
- [x] `stylized_flame_snapshot.json` intentionality confirmed (is it a baked preset or in-progress junk?).

### README
- [x] `README.md` exists at repo root.
- [ ] 150-220 lines.
- [x] Section order matches the doctrine above (hero media at position 2, not buried).
- [x] Every external reference (Godot version, features list) matches [project.godot](../../project.godot) ground truth.
- [x] All relative links resolve.
- [x] Mermaid diagrams (if any) render on GitHub preview.
- [x] Badges ≤4, none of them a red CI badge.

### Architecture suite
- [x] `docs/architecture/` exists with 5 files + VERIFY.md + README.md = **7 files total**.
- [x] Total suite length ≤1500 lines; target ~900.
- [x] 3 Mermaid diagrams total (scene tree flowchart, Ship FSM stateDiagram-v2, player-damage sequenceDiagram).
- [x] Signal sequenceDiagram uses `->>` / `-->>` distinction for calls vs signals.
- [x] Every code reference uses function-name prose anchors or bare `file_path` links — no `#Lxx` ranges except where a specific line is the whole point.
- [x] Each content file opens with "What you'll know" (3-4 bullets) and closes with "What to read next."
- [x] Each content file has a `<!-- verified against commit <sha> on <date> -->` stamp.
- [x] Every ADR (001–014) referenced at least once across the suite (forces "is this ADR still load-bearing" audit).
- [x] ADR map paragraph in architecture README covers all 14.
- [x] Read end-to-end in a single pass: no forward-references that break ordering.

### Phase 1.5 dogfood
- [x] Cold reader (user or fresh agent) reads `docs/architecture/README.md` + `01-overview.md` + `03-entities-and-components.md` — in that order — and answers the 3 seed questions (below). Any question that can't be answered → gap logged and fixed before Phase 2.

### GitHub readiness
- [x] `.gitignore` updated to Appendix A contents.
- [x] `LICENSE` (MIT) at repo root.
- [x] If third-party assets exist, `assets/CREDITS.md` created; else README credits section says "all assets self-made".
- [ ] `gh repo view` (after push) shows description + topics + README preview correctly.
- [ ] Repo visibility deliberately flipped from private → public after a final README skim (not auto-public).

### Web export + Pages deploy (new in v3)
- [x] `export_presets.cfg` `export_path` changed to `build/web/index.html`.
- [x] `variant/thread_support=false` confirmed in the Web preset (non-negotiable — anything else breaks Pages hosting).
- [x] `.github/workflows/deploy-pages.yml` present with Appendix D contents.
- [ ] Pages enabled in repo Settings with Source = "GitHub Actions".
- [ ] First deploy green; URL accessible in a browser.
- [ ] Game actually runs in the browser: loads, plays a wave, fires cannons, drops mines, shows explosions, minimap works. **Smoke test in Chrome AND Firefox** — WebGL2 behavior differs.
- [ ] `.nojekyll` marker present in `build/web/` (added by workflow).
- [ ] README "Play it in browser" link updated to the live URL.
- [ ] `gh repo edit --homepage <pages-url>` run.
- [ ] Load time and initial download size noted in README dev section (set expectations — 20-40 MB is normal).

### Quality gates
- [x] `gdformat --check` clean (docs change shouldn't affect this; sanity run).
- [x] `gdlint .` clean.
- [x] `gut -gdir=res://tests/unit -gexit` clean.
- [ ] Editor manually opened once: zero error spam in output panel.

## Implementation Phases

### Phase 0 — Pre-flight (do this first, non-negotiable)

All the cheap checks that prevent Phase 1 from building on a bad foundation.

1. **Clean working tree.** Resolve the pending rename (`pixel-water-shader.md → docs/pixel-water-shader-reference.md`) and the modified `2026-04-04-feat-pixel-water-shader-prototype-plan.md`. Commit or stash. `git status` must be clean.
2. **Smoke run.** F5 in the editor. Play 30 seconds. Confirm zero errors in output. Confirm explosions, water, dash, cannons, mines all work. If something is broken, FIX IT before writing docs — otherwise the docs propagate a broken state.
3. **Hygiene grep.** `grep -rn "print(" features/ systems/ autoload/ main/` → triage each. `grep -rn "TODO\|FIXME" features/ systems/` → categorize. Legitimate `TODO(post-mvp)` in shaders is fine; untriaged FIXMEs are not. Delete `handoff.md`, `scratch.md`, `notes.md` if present at repo root. Confirm `.mcp.json` and `.claude/` are ignored.
4. **ADR staleness audit.** Skim ADRs 001–014. For each, mark in a scratch note: `current` / `superseded` / `needs-errata`. The component refactor just landed; some pillar ADRs may predate it. Any "needs errata" item lands in the architecture README ADR map paragraph in Phase 1.
5. **`stylized_flame_snapshot.json` intentionality check.** Is it a baked preset (keep, document in 04-resources-and-vfx.md) or in-progress junk (delete)? Decide now, not in Phase 3.
6. **Hero media capture.** Record a 3-5 second gameplay GIF via OBS or built-in screen record → ffmpeg → gifski. Save to `docs/media/hero.gif`. **If the game doesn't look ready for a GIF yet**, commit a placeholder `docs/media/hero.png` screenshot with a note in README "TODO: replace with gameplay GIF before visibility flip".
7. **Commit.** `chore: pre-flight sweep for docs pass` (a single commit for cleanup; media is separate: `docs: add hero media placeholder`).

**Gate:** do not proceed to Phase 1 until all six items above are done. The cost of skipping one is high (doc rework); the cost of doing them is an hour.

### Phase 1 — Architecture Suite

Writing the architecture tour first forces a re-read in onboarding voice, which surfaces README content naturally.

1. **Scaffold** `docs/architecture/` with 5 stub files + README.md + VERIFY.md. Each stub opens with `<!-- verified against commit <Phase-0-commit-sha> on 2026-04-08 -->` and the "What you'll know" contract.
2. **`01-overview.md`** — fastest to write, grounds everything. Godot version, game concept, run loop sequence diagram, scene tree walkthrough.
3. **`03-entities-and-components.md`** — written second (not third) because the component table is the highest-value artifact and getting it right shapes the rest. Ship FSM stateDiagram-v2 here.
4. **`02-autoloads-and-signals.md`** — autoload inventory + the single player-damage sequenceDiagram. Written after 03 so the vocabulary (HurtboxComponent, HealthComponent, `_on_hurtbox_hit`) is already locked in.
5. **`04-resources-and-vfx.md`** — resource catalog + ADR 009 in onboarding voice + water/vfx pointers (do NOT duplicate [docs/pixel-water-shader-reference.md](../pixel-water-shader-reference.md)).
6. **`VERIFY.md`** — one-screen manual checklist. Written before the index README so the index can link to it.
7. **Index `README.md`** — written last. "Read in this order," "15-min path," ADR map paragraph (absorbs the cut 10-adr-index.md).
8. **Anchor sweep.** Final Phase 1 step: grep `docs/architecture/` for every `.gd` / `.tscn` reference, confirm each file exists, confirm function-name anchors are still valid symbols. Fix any stragglers.

**Commit cadence:** one commit per file, `docs(architecture): add <filename>`. Seven commits total. Between commits in Phase 1, **do not edit referenced source files** — if a bug surfaces, land the fix either before Phase 1 or after, not mid-pass (prevents line-shift within the same PR).

### Phase 1.5 — Dogfood (the only validation that matters)

Spawn a cold reader — user themselves, or a fresh agent — and hand them `docs/architecture/README.md` + `01-overview.md` + `03-entities-and-components.md` (in that order) with nothing else. **Ask them to answer three seed questions without reading source code:**

1. *"When the player takes cannonball damage, which component runs first, and where does the death signal ultimately fire?"* (Tests whether 03 → 02 signal flow is clear.)
2. *"If I wanted to add a new enemy type, which files would I touch?"* (Tests whether the entity+component model is clear without the cut cookbook.)
3. *"Which autoload is responsible for respawn state, and why is main.gd so thin?"* (Tests whether 01 + 02 + ADR 010 are linked together.)

For each question that can't be answered from the docs: log the gap, fix the relevant file, re-run. Cap at 2 dogfood passes. If a third is needed, the architecture suite is structurally wrong and needs a shape rethink.

**Commit:** `docs(architecture): dogfood fixes` (one commit if any fixes; skip if clean).

### Phase 2 — README.md

1. **Gather ground truth** — re-read [project.godot](../../project.godot), [CLAUDE.md](../../CLAUDE.md), current controls from [features/hud/controls_overlay.gd](../../features/hud/controls_overlay.gd).
2. **Draft README.md** at repo root following the section order above.
3. **Link-check** — every relative link resolves.
4. **Badge picker** — 3-4 only: Godot version, MIT license, last-commit. Skip CI badge.
5. **Commit** — `docs: add README.md`.

### Phase 3 — GitHub-Readiness Sweep (thin)

Phase 0 already handled hygiene + ADR audit + media. Phase 3 is just the three publication artifacts.

**Step A. `.gitignore` patch.** Apply Appendix A. Must include `/build/` (the new Web export output directory — do not commit generated `.wasm`/`.pck`/`.html`). Commit: `chore(gitignore): audit pre-publication`.

**Step B. LICENSE (MIT).** Write standard MIT text, copyright Alan 2026. Commit: `chore: add LICENSE (MIT)`.

**Step C. Credits conditional.** If third-party assets exist, create `assets/CREDITS.md`; else add "all assets self-made" to README credits section (may already be there from Phase 2). Commit only if a file was created: `docs: add asset credits`.

**Step D. Export preset tweak.** Edit [export_presets.cfg](../../export_presets.cfg): change `export_path="../PirateShipGameWeb/index.html"` → `export_path="build/web/index.html"`. Verify `variant/thread_support=false`. Test locally with `godot --headless --export-release "Web" build/web/index.html` — should produce `index.html`, `index.wasm`, `index.pck`, plus a few support files in `build/web/`. Delete `build/` afterwards (it's gitignored). Commit: `chore(export): point Web preset at build/web/`.

**Step E. Deploy workflow.** Create `.github/workflows/deploy-pages.yml` with Appendix D contents. Verify the YAML parses (`actions/workflow-parser` if you want to be sure, else just push and watch). Commit: `ci: add GitHub Pages deploy workflow`.

**Step F. Enable Pages + first deploy.** In repo Settings → Pages → Source: **"GitHub Actions"**. Trigger first run via `gh workflow run deploy-pages.yml` or by pushing any commit. Watch the Actions tab. When green, note the URL from the job summary. **Open it in Chrome and Firefox and actually play a wave.** If it 404s, broken images, or errors in console — diagnose before declaring the step done (see "Gotchas" in Appendix D).

**Step G. Update README with live URL.** Edit the README "Play it in browser" section to link to the real URL. Commit: `docs: add live Play-it link to README`.

**Step H. Visibility flip gate.** Before flipping private → public:
- [ ] README skimmed once in GitHub preview (push to private remote first if needed).
- [ ] Hero media is real, not placeholder (unless user explicitly accepts placeholder-first).
- [ ] **Pages deploy is green and the live URL actually loads the game.** This replaces the old "no red CI badge" rule — the deploy workflow badge is fine if it's green.
- [ ] No obvious embarrassments (broken links, stale TODOs, debug prints).

**Step I. `gh repo edit` metadata.** Description, topics, `--homepage <pages-url>` (now a real URL), social preview upload. Not a commit.

## Alternatives Considered

**Keep the 10-file architecture suite.** Rejected. Two independent reviewers (simplicity + best-practices) converged on "too granular for a solo project." Forward-references between files break the onboarding ordering. A 5-file merged suite matches the codebase's actual seams (entities-with-components, autoloads-with-signals, resources-with-vfx).

**Single monolithic `ARCHITECTURE.md` (matklad pattern).** Considered. Works for rust-analyzer, Zed, others. Rejected for this project because the 5-file split matches Godot's natural scene/autoload/resource seams and lets commits land incrementally without a 1200-line rebase magnet. The 5-file suite is the compromise between matklad's monolith and the original 10-file over-split.

**Keep the cookbook (09-adding-things.md).** Rejected. Solo-dev recipes for code you wrote yesterday have near-zero re-read value and guaranteed rot. Best-practices agent's concession ("cap at 6 recipes, 30 lines each") was evaluated and still deemed too much maintenance surface vs value.

**Ship test-CI in Phase 3.** Rejected. A red CI badge on first public push is the exact embarrassment the plan is trying to avoid. Commands exist locally per CLAUDE.md. Appendix B preserves the ready-to-paste workflow for future adoption. **(Note: deploy-CI for Pages IS shipped in v3 — different workflow, different trade-off. Deploy-CI producing a visible live URL pays for itself immediately; test-CI producing a redundant green check does not.)**

**Host the Web build on itch.io instead of Pages.** Rejected in v3. The usual argument for itch.io over Pages is the COOP/COEP header requirement, which Pages cannot satisfy — but this project's export preset has `variant/thread_support=false`, which removes the requirement entirely. Pages also gives a cleaner URL under the same GitHub account, auto-deploys on push, and keeps the build inside the repo's commit graph. Itch.io remains a valid fallback if you ever enable thread support or want a separate storefront listing.

**`.github/` scaffold now.** Rejected. Issue templates + PR template for zero external contributors is LARP. Added the day the first external issue lands.

**Generate architecture docs from code comments.** Rejected. Godot has no `godoc`-class extractor with narrative fidelity. Generated doc rot is usually worse than hand-written rot.

**Line-range anchors (`#L30-L50`) for rot tolerance.** Rejected after research — they rot at the same rate as exact lines and add noise. Function-name anchors + last-verified stamps + VERIFY.md manual recheck is the better trade.

**Skip README because CLAUDE.md exists.** Rejected. Different audiences.

**Skip LICENSE (all rights reserved).** Rejected. Legal footgun on public GitHub; users can't legally fork or play. MIT matches Godot convention at zero cost.

## Open Questions

Reduced from 6 to 1. Five were resolved inline via research + defaults:

- ~~License choice~~ → **MIT** (decided; framework-docs Godot-convention rationale).
- ~~CI now or deferred~~ → **Deferred** (decided; simplicity + CI-red-on-first-push risk).
- ~~`.vscode/` ignored or committed~~ → **Ignored** (default; no shared settings exist yet).
- ~~Visibility flip timing~~ → **Private-first, flip after final README skim** (default).
- ~~Asset credits walking-tree audit~~ → **One-line conditional** (collapsed; no phase needed).

**Remaining open question:**

1. **Hero media: real GIF now or placeholder first?**
   - Option A: Record a real gameplay GIF in Phase 0, block the pass for 30 minutes of OBS + ffmpeg + gifski. Best-practices research says GIF dramatically outperforms static images for game-repo engagement.
   - Option B: Commit a static screenshot placeholder in Phase 0, capture the GIF post-Phase-2 before the visibility flip. Risk: it slides and the repo goes public with a placeholder.
   - **Default:** Option B (placeholder first) because the visibility flip is the real gate and placing the GIF earlier blocks Phase 0 on a recording session.

## Future Considerations

- **CHANGELOG.md** — on first tagged release, not now.
- **CONTRIBUTING.md** — when the first external contributor appears.
- **Test-CI workflow (Appendix B)** — when a collaborator joins, or when pre-commit local discipline slips. Deploy-CI (Appendix D) already ships in v3.
- **itch.io secondary listing** — Pages is the primary host (v3), but a duplicate itch.io page is worth ~30 minutes of upload time if you want discoverability inside the itch community. Same build, two hosts.
- **PR preview deploys** — separate `.github/workflows/preview.yml` that builds PRs into `/preview/<pr-number>/` subdirectories. Only worth it if external contributors start arriving.
- **Screenshots gallery** — `<details>` collapsible section in README with 3-5 in-game shots. After the hero GIF is landing.
- **ADR template file** at `docs/decisions/TEMPLATE.md` — 10-minute follow-up to this plan.
- **Architecture diagram as a single SVG poster** — nice-to-have; fights the "docs live as text in-repo" rule. Revisit if the 3 Mermaid diagrams prove insufficient.
- **Pre-commit hook running gdformat/gdlint/gut** — local enforcement of CLAUDE.md conventions. Lighter-weight than CI.

## Sources & References

### Internal
- [docs/plans/2026-04-07-refactor-component-architecture-plan.md](2026-04-07-refactor-component-architecture-plan.md) — the just-landed refactor this docs pass documents.
- [CLAUDE.md](../../CLAUDE.md) — agent conventions; cross-linked from the architecture suite.
- [docs/decisions/](../decisions/) — ADRs 001–014; audited in Phase 0 Step 4, referenced from architecture README.
- [docs/pixel-water-shader-reference.md](../pixel-water-shader-reference.md) — existing shader doc; linked from `04-resources-and-vfx.md`, never duplicated.
- [docs/solutions/](../solutions/) — institutional learnings; candidate cross-links.
- [main/main.gd](../../main/main.gd) + [main/main.tscn](../../main/main.tscn) — entry point, subject of `01-overview.md`.
- [project.godot](../../project.godot) — source of truth for Godot version, autoload list, viewport config.

### External (from research)
- Godot 4 project-organization / version-control best practices: https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html#version-control-systems
- Godot FAQ on license: https://docs.godotengine.org/en/stable/about/faq.html#what-license-does-godot-use
- Godot UID system docs: https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html#using-uids
- `chickensoft-games/setup-godot@v2` marketplace action: https://github.com/chickensoft-games/setup-godot
- `gdtoolkit` (gdformat, gdlint): https://github.com/Scony/godot-gdscript-toolkit
- Godot Web export + COOP/COEP requirement: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- GitHub issue-template form schema: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository
- Mermaid syntax reference: https://mermaid.js.org/
- Matklad on ARCHITECTURE.md: https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html

---

## Appendix A — `.gitignore` (ready-to-paste replacement)

```gitignore
# Godot 4
.godot/
/android/build/
/ios/
/export/
/builds/
/build/                 # Web export output target (Appendix D deploy workflow)
*.translation
export_credentials.cfg

# OS / editors
.DS_Store
Thumbs.db
*.swp
*~
.idea/
.vscode/

# Project-specific
test/results/

# Claude Code / dev agents
.claude/
.mcp.json
.worktrees/
```

**Notes:**
- `.gd.uid` sidecars are NOT in this list — they MUST be committed (ADR 010 §6, Godot 4.4+ script UID resolution).
- `export_presets.cfg` is NOT in this list — it's Godot convention to commit it. `export_credentials.cfg` (separate file Godot auto-creates when signing exports) IS ignored.
- `.godot/` covers all Godot 4 import caches; no separate `.import/` entry needed (that was Godot 3).
- `addons/gut/` and `addons/pirate_dev_tools/` are vendored and intentionally committed — not in the ignore list.

## Appendix B — Deferred CI workflow (for future adoption)

If the CI decision is ever revisited (new collaborator, local discipline slipping, etc.), this workflow is ready to paste at `.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: chickensoft-games/setup-godot@v2
        with:
          version: 4.6.1
          use-dotnet: false

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install gdtoolkit
        run: pip install "gdtoolkit==4.*"

      - name: Cache .godot import folder
        uses: actions/cache@v4
        with:
          path: .godot
          key: godot-import-${{ hashFiles('**/*.tscn', '**/*.tres', '**/*.gd', 'project.godot') }}

      - name: Import project (headless)
        run: godot --headless --import || true

      - name: gdformat --check
        run: |
          find . -name "*.gd" \
            -not -path "./addons/*" \
            -not -path "./.godot/*" \
            -print0 | xargs -0 gdformat --check

      - name: gdlint
        run: gdlint .

      - name: GUT unit tests
        run: |
          godot --headless \
            -s addons/gut/gut_cmdln.gd \
            -gdir=res://tests/unit \
            -gexit
```

**Gotchas for future-you:**
- `godot --headless --import || true` is intentional — first import exits non-zero on normal warnings.
- `.godot/` cache keyed on scene/resource/script hashes gives ~10× speedup after first run.
- gdtoolkit 4.x is the Godot-4 branch (`gdtoolkit==4.*`), not the default 3.x.
- `exclude` the `addons/` directories from gdformat but not from gdlint (gdlint reads `gdlintrc` for excludes).
- If a red run is embarrassing, add `continue-on-error: true` to individual steps while stabilizing, then remove it.

## Appendix C — Mermaid conventions cheat sheet

For consistency across the 3 diagrams in the architecture suite.

**Scene-tree flowchart (01-overview.md):**
```
flowchart TD
    Main[main.tscn] --> Ship[Ship]
    Main --> WD[WaveDirector]
    Main --> SS[SpawnService]
    Events[[Events autoload]]
    GS[[GameState autoload]]
    Ship -.emits.-> Events
```
- `[[Box]]` for autoloads, plain `[Box]` for scene nodes.
- `subgraph` for feature groupings if needed.
- Dashed `-.label.->` for signal emits, solid `-->` for scene-tree parent/child.

**Ship FSM (03-entities-and-components.md):**
```
stateDiagram-v2
    [*] --> NORMAL
    NORMAL --> DASHING: dash_requested
    DASHING --> NORMAL: dash_ended
    NORMAL --> INVINCIBLE: damage_taken
    INVINCIBLE --> NORMAL: iframes_ended
    NORMAL --> DEAD: death_requested
    DEAD --> NORMAL: respawn
```
- `stateDiagram-v2` (not `stateDiagram`).
- Transition labels are the signal / reason.

**Player-damage sequence (02-autoloads-and-signals.md):**
```
sequenceDiagram
    participant Cannonball
    participant Hurtbox as HurtboxComponent
    participant Ship
    participant Health as HealthComponent
    participant Events as Events bus
    participant Main as main.gd

    Cannonball->>Hurtbox: area_entered
    Hurtbox-->>Ship: hit_registered
    Ship->>Health: apply_damage(amount)
    Health-->>Ship: death_requested
    Ship-->>Events: player_died
    Events-->>Main: respawn coordination
```
- `->>` for direct method calls.
- `-->>` for signal emissions.
- Participants ordered left-to-right by first mention.
- Cap at 6 participants (GitHub column width).

## Appendix D — Web export + GitHub Pages deploy workflow

**In-scope** for Phase 3 (unlike Appendix B's test-CI workflow, which remains deferred). This workflow builds the Godot Web export on every push to `main` and deploys it to GitHub Pages.

**Why this project can use Pages at all:** [export_presets.cfg](../../export_presets.cfg) has `variant/thread_support=false`, so the exported game does not require `SharedArrayBuffer`, which means no COOP/COEP cross-origin-isolation headers are needed, which means plain static hosting (GitHub Pages) works. **If you ever flip `thread_support=true`, this workflow stops working and you need itch.io or a custom host instead.**

### File: `.github/workflows/deploy-pages.yml`

```yaml
name: Deploy Web Build to Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup Godot 4.6.1
        uses: chickensoft-games/setup-godot@v2
        with:
          version: 4.6.1
          use-dotnet: false
          # chickensoft-games/setup-godot@v2 installs export templates
          # by default — no separate download step needed.

      - name: Cache .godot import folder
        uses: actions/cache@v4
        with:
          path: .godot
          key: godot-import-${{ hashFiles('**/*.tscn', '**/*.tres', '**/*.gd', 'project.godot') }}
          restore-keys: |
            godot-import-

      - name: Import project (first pass)
        run: godot --headless --import || true

      - name: Export Web build
        run: |
          mkdir -p build/web
          godot --headless --export-release "Web" build/web/index.html
          # .nojekyll prevents Pages' Jekyll processor from stripping
          # files whose names start with an underscore.
          touch build/web/.nojekyll

      - name: List build output (sanity log)
        run: ls -lh build/web/

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: build/web

      - name: Deploy to Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### Prerequisites before first run

1. **Enable Pages.** Repo Settings → Pages → Source dropdown → select **"GitHub Actions"** (not "Deploy from a branch"). Without this, the `deploy-pages@v4` step fails with a permissions error.
2. **Export preset path.** [export_presets.cfg](../../export_presets.cfg) must have `export_path="build/web/index.html"`. The old `../PirateShipGameWeb/index.html` writes outside the workspace and the runner will error.
3. **`/build/` in `.gitignore`.** Already in Appendix A. Confirm before pushing to avoid committing a 20+ MB binary blob by accident.
4. **Thread support off.** `variant/thread_support=false`. Non-negotiable for Pages compatibility.

### Expected first-run behavior

- **Duration:** 2-4 minutes. First run is slower because the `.godot/` cache is empty.
- **Subsequent runs:** 60-90 seconds with cache hit.
- **Artifact size:** ~20-40 MB depending on texture compression and asset count.
- **URL:** `https://<your-github-username>.github.io/PirateShipGame/` — visible in the "Deploy to Pages" step output under "page_url".
- **First browser load:** 5-15 seconds on a typical connection. Godot's default loading bar is shown. Unavoidable.

### Gotchas and troubleshooting

1. **Subpath routing.** The game lives at `/PirateShipGame/`, not at the domain root. Godot's default exported `index.html` uses relative paths, which is correct. If you ever hardcode an absolute `/something` URL in GDScript (for loading a resource, etc.), it will break on Pages. `res://` paths are always fine.
2. **Audio silent until first click.** Browsers block audio autoplay. Godot 4 handles it, but expect the first frame to be silent. Not a bug.
3. **WebGL2 divergence.** Chrome and Firefox render shaders slightly differently. The pixel-water shader may look marginally different. Test in both.
4. **VRAM texture compression.** The export preset has `vram_texture_compression/for_desktop=true`. This works in WebGL2 but produces larger `.wasm` than expected. If download size becomes a problem, flip to false and accept higher GPU memory usage — trade-off.
5. **Green deploy, blank page.** Almost always a missing `.nojekyll` file. The workflow above creates it via `touch build/web/.nojekyll` — do not remove that line.
6. **Broken Pages after repo rename.** If you rename the repo later, the Pages URL changes (`/OldName/` → `/NewName/`). Update the README link and `gh repo edit --homepage`.
7. **403 Forbidden on deploy step.** The `permissions:` block at the top of the workflow is mandatory. `pages: write` and `id-token: write` are both required by `actions/deploy-pages@v4`.
8. **First deploy on a fresh branch.** Pages deploys only from the branch(es) you configure. Default config above triggers on `main` pushes + manual `workflow_dispatch`. PRs do not deploy (intentional — prevents preview-URL sprawl).

### What this workflow deliberately does NOT do

- **Does not run tests.** That's Appendix B's test-CI workflow, still deferred. If you want tests + deploy in one workflow, merge them manually later — but keep them as separate jobs so a test failure doesn't block an already-working deploy.
- **Does not export for other platforms.** Web only. Desktop/mobile exports stay manual via the Godot editor.
- **Does not version or tag releases.** First run always overwrites `gh-pages`. If you want versioned previews (`/v1/`, `/v2/`), that's a bigger plan — current approach assumes rolling-latest is fine.
- **Does not deploy on PRs.** Prevents preview-URL sprawl and `permissions` abuse from forks. If you want PR previews later, add a separate `preview.yml` with `pull_request` trigger.

---

*Plan v3 — Web export + Pages deploy folded in 2026-04-08. v2 and v1 preserved in git history at this path.*
