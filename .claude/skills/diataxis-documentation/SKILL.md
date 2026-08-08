---
name: diataxis-documentation
description: "Structure, classify, write, and review documentation using the Diátaxis framework (tutorials, how-to guides, reference, explanation). Use when authoring or restructuring docs, READMEs, guides, tutorials, or API references, when deciding which type of document a request needs, or when reviewing existing documentation for mixed or misplaced content."
---

# diataxis-documentation

Apply the [Diátaxis](https://diataxis.fr/) framework when creating or
maintaining documentation. Its core claim: there are exactly four kinds of
documentation, each serving a different user need, and a page that mixes them
serves none well.

## The four types

Two axes classify every piece of documentation: is the user **acquiring**
skill (studying) or **applying** it (working), and does the content guide
**action** (doing) or inform **cognition** (understanding)?

| Type | User need | Form | Tone |
|---|---|---|---|
| Tutorial | Learn by doing | A lesson toward one concrete result | "We will…", encouraging, zero detours |
| How-to guide | Get a task done | Numbered steps toward a stated goal | "If you want X, do Y", assumes competence |
| Reference | Look up facts | Structured description of the machinery | Neutral, austere, consulted not read |
| Explanation | Understand why | Discursive discussion of a topic | "About X", context, trade-offs, opinion allowed |

## Workflow: writing a new document

1. **Classify the request.** Ask two questions: action or cognition?
   acquisition or application? The intersection names the type. Common traps:
   - "Getting started" is a tutorial (learning), not a feature tour.
   - "How do I…" from a competent user is a how-to guide — don't teach basics.
   - "What are the options for…" is reference — describe, don't advise.
   - "Why does it work this way" is explanation — context, not instructions.
2. **Name the audience and the outcome** before writing: who reads this, and
   what can they do or answer afterwards? If you cannot state one outcome,
   the scope is wrong.
3. **Write to the type's rules:**
   - *Tutorial*: pick one achievable result, show visible progress early and
     often, aspire to perfect reliability (every step must work exactly as
     written), and ruthlessly cut explanation — link to it instead.
   - *How-to guide*: title it "How to <goal>", order the steps by the work,
     omit anything not needed for the goal, mention alternatives briefly.
   - *Reference*: mirror the structure of the product, keep entries uniform
     and factual, generate or verify API/option lists from the source of
     truth rather than writing them from memory.
   - *Explanation*: bound the topic, make connections, give the why —
     history, constraints, alternatives, design reasoning.
4. **Link across types instead of embedding.** A tutorial links to reference
   for details and to explanation for background; a reference entry links to
   the how-to that uses it. Embedding one type inside another is the main
   failure mode.
5. **Include runnable examples where the type calls for them** (tutorial and
   how-to steps, reference usage snippets) and verify commands and code
   actually work before publishing.

Do not scaffold empty `tutorials/ how-to/ reference/ explanation/` trees up
front. Let structure emerge from content that exists; follow the repository's
existing docs layout and language.

## Workflow: reviewing existing documentation

Check each page against the type it claims (or its location implies) to be:

1. Does the page serve one type? Flag sections that switch mode — teaching in
   the middle of reference, option dumps in a tutorial, step lists in an
   explanation.
2. Is content duplicated across pages of different types? Keep one canonical
   home per fact and link to it from elsewhere.
3. Does the title match the type (tutorial: what you'll build; how-to: the
   goal; reference: the thing; explanation: the topic)?
4. Is reference material verifiable against the code or API it describes?
   Stale reference is worse than none.

**Recommend splitting when one page serves incompatible purposes.** A page
that both teaches a beginner and serves as a lookup table should become a
tutorial plus a reference page, cross-linked — not a longer combined page.
Propose the split; move content in the same change only when the task allows.

## Mixed requests

Requests often combine needs ("document the new feature" usually implies a
how-to *and* reference updates). Decompose into one document (or section)
per type, state the decomposition to the user, and write the pieces in the
order that serves the reader: usually reference first (facts), then how-to,
then tutorial or explanation if warranted.
