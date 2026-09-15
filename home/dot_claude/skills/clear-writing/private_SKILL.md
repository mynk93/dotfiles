---
name: clear-writing
description: >
  Revise prose for clarity and signal using four named methods: Minto's
  pyramid for structure, Williams's character/action and cohesion for
  paragraphs, Lanham's Paramedic Method for sentences, and Klinkenborg's
  rhythm rules for cadence. Use this skill whenever the user asks to tighten,
  clarify, de-bloat, restructure, or "make cleaner" any piece of writing, or
  says a draft reads as buried, flabby, wordy, hard to skim, or "like an LLM
  wrote it." Applies to memos, status updates, recommendations, design docs,
  Slack posts, emails, and any writing aimed at a busy reader who wants the
  point first. Trigger it even when the user just pastes text and says "fix
  this" or "too long," not only when they name a method.
---

# Clear Writing

Revise writing so an intelligent, time-poor reader gets the point fast and
trusts it. The reader is a peer, not a student. Lead with the answer. Cut
anything that is not load-bearing. Use concrete nouns and strong verbs.

This skill works in two passes, in order. Pass 1 fixes structure: where
things go. Pass 2 fixes the line: how each sentence runs. Do not run both at
once. Line-editing a sentence that is about to be moved or cut is wasted
work, so settle the structure first.

If the user wants a review instead of a rewrite, skip the rewriting and use
the same checks to flag passages, name the method each one violates, and
give the fix.

---

## Pass 1 — Structure (the macro layer)

### 1. Put the answer first (Minto's Pyramid Principle)

State the single governing point before any support. The reader should know
your conclusion or recommendation from the first sentence and be able to stop
reading the moment they are convinced.

Open with SCQA when the piece needs framing:
- **Situation:** the context the reader already accepts.
- **Complication:** what changed or what is now in tension.
- **Question:** the question that tension raises.
- **Answer:** your governing point. This is also your opening line.

Then arrange the support as a pyramid. Every point summarizes the points
beneath it. Group the supporting points so they are mutually exclusive (no
overlap) and collectively exhaustive (no gaps). Inside one group, use a
single logic: either deductive (premise, premise, therefore) or inductive (a
set of like items named by one plural noun). Do not mix the two inside a
group.

Apply the "so what?" test to every point. If a point does not answer the
question raised by the point above it, it is not support. Cut it or move it.

**Before** (conclusion buried at the end):

> Over the last quarter we evaluated three vendors for the STT pipeline.
> Vendor A had latency problems in our load tests. Vendor B came in cheaper
> but offered no regional redundancy. After several calls with each team and
> a full review of the benchmarks, we have concluded that Vendor C is the
> right choice.

**After** (answer first, support below):

> Recommendation: choose Vendor C for the STT pipeline. It was the only one
> of the three that cleared both our latency and redundancy bars. Vendor A
> failed the latency load tests; Vendor B had no regional redundancy. Cost
> and benchmark detail are in the appendix.

### 2. Make the paragraph cohere (Williams)

A clean sentence in an incoherent paragraph still reads as muddy. Three
checks:

**Topic strings.** The subjects of consecutive sentences should form a
consistent set the reader can track, so the paragraph is visibly *about*
something. Diagnose it by reading only the first few words of each sentence.
If those openers jump between unrelated topics, the paragraph will feel
scattered even when each sentence is correct.

**Old-to-new flow.** Open each sentence with information the reader already
has; end it with what is new. Let the new thing become the familiar opener of
the next sentence. That chaining is what people experience as flow.

**Point in a predictable place.** Readers look for the point of a paragraph in
two places: the last sentence of a short intro, or the first sentence of the
body. Put it in one of them. Do not make the reader hunt.

**Before** (subjects scatter: migration, latency, improvement, finance):

> The migration finished last week. Latency was the next thing the team
> measured. A 12% improvement was the result. Cost concerns are still held by
> finance.

**After** (topic string stays on the work; old-to-new chains):

> We finished the migration last week, then measured latency. It improved
> 12%. The one open item is cost, which finance still wants to review.

---

## Pass 2 — The line (the micro layer)

### 3. Character and action (Williams)

Make the subject of the sentence the character who acts, and make the verb
the action they take. The most common failure is the nominalization: an
action hidden inside a noun, propped up by a weak verb like *make*, *provide*,
*conduct*, *perform*, or a form of *to be*.

Find the nominalization, recover the buried verb, give it back to the person
or thing doing it.

- "make a decision" → "decide"
- "provide assistance to" → "help"
- "conduct an investigation of" → "investigate"
- "there was a reduction in costs" → "costs fell" (or name who cut them)

**Before:**

> The implementation of the new caching layer resulted in a reduction of
> inference costs.

**After:**

> The new caching layer cut inference costs. *(Or, with the actor restored:
> "We added a caching layer and cut inference costs.")*

### 4. The Paramedic Method (Lanham)

A mechanical drill for any sentence that feels heavy. Run the steps in order:

1. Circle every preposition (*of, in, to, for, by, with, regarding*). Long
   prepositional chains are where action goes to hide.
2. Circle every form of *to be* (*is, are, was, were, been, being*).
3. Ask what is actually happening in the sentence, and who is doing it.
4. Rebuild: the doer becomes the subject, the action becomes a strong verb.
5. Start fast. Delete the windup ("It is important to note that...", "What I
   am trying to say is...", "There is a need for the team to...").
6. Read the result aloud.

Track the **lard factor**: count the words before and after. On bloated prose,
a cut of 30 to 50 percent is normal and almost always an improvement.

**Before** (30 words):

> It is important to note that the decision regarding the deprecation of the
> legacy endpoint was made by the platform team after a consideration of the
> migration risks.

**After** (11 words; lard factor ~63%):

> The platform team deprecated the legacy endpoint after weighing migration
> risk.

### 5. Rhythm (Klinkenborg)

Treat the sentence as the unit of composition. Get each one right before
worrying about how they join.

- **Default to short.** A short sentence cannot hide a confused thought. A
  long one usually is one you have not finished thinking.
- **Vary length by ear.** Put a short sentence after a long one. Read aloud
  and listen; rhythm carries meaning, so control it on purpose. Uniform
  medium-length sentences are the clearest signature of machine prose.
- **Each sentence makes one move.** Know what the move is.
- **Distrust transitions.** If the sentences are in the right order, they
  connect themselves. *Moreover*, *Furthermore*, and *Additionally* usually
  paper over a sequencing problem. Fix the order instead of adding the word.
- **Trust the reader to connect the dots.** Leaving the obvious inference to
  the reader is what respect reads like. Spelling it out is what condescension
  reads like.

**Before** (metronomic, every sentence the same length and shape):

> The model performed well in testing. The latency was within our target
> range. The cost was somewhat higher than expected. We will monitor it over
> the coming month.

**After** (varied length, one short beat, transitions dropped):

> The model passed testing. Latency landed inside target. Cost ran high,
> higher than we modeled, so we will watch it for a month.

---

## Calibration — what not to "fix"

Over-correction produces its own kind of dead prose. Leave these alone:

- **Legitimate triads.** Three items are a problem only when the third is
  padding or a near-synonym of the first two. A real list of three real
  things is fine.
- **A long sentence doing real work.** Length is not the enemy; aimlessness
  is. If a long sentence builds and the reader can follow it in one breath,
  keep it.
- **Passive voice with a reason.** Passive is correct when the doer is
  unknown, irrelevant, or less important than the thing acted on ("The server
  was rebooted at 02:00"). Do not convert it reflexively.
- **Repetition over elegant variation.** When one word is the clearest word,
  repeat it. Do not cycle through synonyms ("the model... the system... the
  engine...") to avoid saying the same noun twice.
- **Specifics.** Never trade a number, name, date, or concrete detail for a
  smoother generality. Vagueness is the enemy, not formality.
- **The author's voice.** The goal is clean, not chatty. Do not inject
  personality, hedges, throat-clearing, or filler warmth that was not there.

---

## Output

**When rewriting:** return the revised text, then a short, scannable note of
the moves you made, grouped by pass. Keep the note to a few lines. Do not
write an essay about the edit.

**When reviewing only:** for each weak passage, quote the span, name the
method it violates (pyramid, cohesion, character/action, Paramedic, rhythm),
and give a concrete fix. Consolidate overlapping issues into one note rather
than inflating the count.

## Final check

Read the whole thing aloud, or imagine reading it to a colleague who is short
on time. Then confirm three things:

1. The first sentence answers the question the reader actually has.
2. Nothing remains that you could cut without losing meaning.
3. Every sentence has a doer and a strong verb, and no two neighbors share the
   same length and shape.

---

## Sources

These methods are drawn from four books. Read them directly for each author's
own voice and full reasoning:

- Barbara Minto, *The Pyramid Principle* — structure and argument.
- Joseph M. Williams, *Style: Lessons in Clarity and Grace* — character/action
  and paragraph cohesion.
- Richard A. Lanham, *Revising Prose* — the Paramedic Method.
- Verlyn Klinkenborg, *Several Short Sentences About Writing* — rhythm and the
  sentence as the unit.
