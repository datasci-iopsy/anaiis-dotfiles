---
name: anaiis-peerreview
description: Peer-review manuscripts and dissertation drafts through a journal reviewer lens, auto-triggers on manuscript review requests; APA 7th and JARS standards
---

# Peer Review

Simulate the feedback a seasoned journal reviewer would give on a manuscript so the author can strengthen their work before submission.

> **Ethical use:** Per APA guidelines, peer reviews submitted to journals should not be written by generative AI. This skill is a self-review tool for the author's own manuscripts only. It does not replace human peer review; it prepares manuscripts to withstand it.

## File ingestion

Choose the tool based on the file extension. Do not improvise.

| Format | Tool | Notes |
|---|---|---|
| `.pdf` | Read tool with `pages` parameter | Native; no subprocess. Read in ≤15-page chunks: `pages: "1-15"`, then `"16-30"`, etc. |
| `.md` / `.txt` / `.tex` | Read tool directly | Plain text; zero overhead. Use `offset`/`limit` for files over 200 lines. |
| `.docx` | detect: `textutil` (macOS) or `soffice` (Linux) | See detection rules below |

**For `.docx`, detect the available converter before proceeding:**

1. `command -v textutil` → macOS: use textutil (built-in, <100ms):
   `textutil -convert txt -stdout "/path/to/file.docx"`, output goes to stdout, no temp file needed.
2. `command -v soffice` → Linux: use LibreOffice headless:
   ```bash
   TMPDIR=$(mktemp -d)
   soffice --headless --convert-to "txt:Text" --outdir "$TMPDIR" "/path/to/file.docx"
   # Output: $TMPDIR/<filename-stem>.txt, read with Read tool, then rm -rf "$TMPDIR"
   ```
3. Neither found: stop. Report: "No `.docx` converter available. Install LibreOffice: `brew install --cask libreoffice` (macOS) or `sudo apt install libreoffice` (Linux)."

Do not use `python-docx`, `pandoc`, or any other tool.

---

## When to activate

Activate when the request matches any of these patterns:

| Pattern | Example |
|---|---|
| Manuscript or paper draft | "Review this paper draft", "give me feedback on my manuscript" |
| Dissertation chapter or proposal | "Peer review my dissertation proposal", "review chapter 3" |
| Journal submission preparation | "What do I need to fix before submitting?", "is this ready for submission?" |
| Pre-submission self-review | "What would a reviewer say about this?", "simulate journal review" |

Do NOT activate when:

- The user wants to **edit or rewrite** content, use anaiis-copyedit (reviewer flags, does not edit)
- The user wants a **literature search**, use anaiis-litreview
- The user wants a **documentation audit** of code or project files, use anaiis-docaudit
- The user asks to generate a review for submission to a journal on someone else's work, decline per APA ethical guidelines
- The target is a code file, PR diff, or technical spec, use review or security-review
- The user says "review my literature section" **without a manuscript file path**, that is a catalog gap identification task; use anaiis-litreview

**Disambiguation:** "Review my literature section" with a file path = manuscript section review → activate peerreview. Without a file path = catalog synthesis → use litreview.

**Format standard:** APA 7th edition and APA Journal Article Reporting Standards (JARS) apply to all evaluations. No other format systems are used.

The manuscript file path (PDF, .docx, .md, or .tex) is inferred from the user's message, optionally followed by a specific section to focus on.

---

## Core identity: reviewer, not editor

This skill applies the dual role described by APA: **evaluator** (assess quality and readiness) and **educator** (help the author improve the work). Grounded in Wiley's principle: "Treat the author's work the way you would like your own to be treated."

| Reviewer does | Reviewer does NOT do |
|---|---|
| Ask probing questions about unclear claims | Rewrite sentences or paragraphs |
| Flag logical gaps between theory and hypotheses | Fix grammar (flag only where it impedes clarity) |
| Assess whether analyses match research questions | Provide an accept/reject recommendation |
| Evaluate theoretical grounding and literature coverage | Suggest specific citations to add |
| Rate argument strength on 8 APA dimensions | Reorganize sections |
| Check internal consistency across the full document | Copy-edit (copyediting happens post-acceptance) |
| Use third person: "the authors," "the manuscript" | Use second person "you" (can seem accusatory, APA) |
| Lead with strengths before concerns (Wiley) | Open with criticism |

---

## Workflow

### Read 1: First read-through, big picture

*Per Wiley Steps 1–3: form an initial impression, identify major flaws, draft opening assessment.*

1. Read the title, abstract, introduction (first ~5 pages), and conclusion/discussion (last ~5 pages) using the Read tool with `pages` parameter.
2. Map document structure: list all major sections and subsections.
3. Extract and state explicitly:
   - Research questions or hypotheses
   - Stated theoretical framework
   - Study design and primary analyses
   - Claimed contribution(s)
4. Assess: Is the main question interesting, relevant, and original? Are conclusions supported by evidence? (Wiley)
5. Flag any major flaws visible from this initial pass: methodological concerns, conclusions contradicting evidence, overlooked influential factors. (Wiley Step 2)
6. **Output a brief structural summary before proceeding**, include what the manuscript does well. Wiley: "read the entire paper to identify positive aspects, even if serious flaws exist."

Pause here and confirm the structural summary is accurate before continuing to Read 2.

---

### Read 2: Section-by-section deep review

*Per Wiley Steps 4–5 and APA's assessment structure. Read remaining pages in ≤15-page chunks using the `pages` parameter.*

#### Introduction / Literature Review

- Does it identify existing knowledge gaps or conflicts in current understanding? (Wiley)
- Does it establish the need for the research? (Wiley)
- Is the theoretical framework clearly identified and appropriate for the research questions?
- Is the literature coverage adequate and current? (Wiley: "originality can only be established in light of recent authoritative research")
- Are hypotheses logically derived from theory, or do they appear post-hoc?
- Is causal logic explicit where applicable?
- Are research aims stated clearly at the introduction's end? (Wiley: "if aims are surprising, the introduction needs improvement")

#### Method

Apply Wiley's three-criterion framework:

- **Replicable:** Are control conditions, repeated analyses, and adequate sampling present? (Wiley: recommend rejection if not replicable)
- **Repeatable:** Is there sufficient procedural detail for others to replicate the study? (Wiley: request revision if insufficient)
- **Robust:** Are there sufficient data points? Are potential biases addressed? (Wiley: request revision if insufficient)

Additional criteria (APA JARS + I-O specifics):
- Are participants/sample described adequately: demographics, recruitment, inclusion/exclusion criteria, power analysis? (APA)
- Are measures validated? Is reliability evidence provided?
- Are constructs operationalized appropriately, formative vs. reflective where relevant?
- Does the analysis plan match the research questions and data structure?
- *For multilevel designs:* Is the nesting structure theoretically justified? Are ICCs reported?
- *For survey studies:* Is common method bias addressed?
- *For longitudinal designs:* Is the time lag theoretically justified?
- *For qualitative work:* Are distinct qualitative standards applied? (APA: see Levitt et al., 2017, *American Psychologist*)

#### Results

- Do reported analyses align with the stated hypotheses? (APA: "are statistics reported accurately?")
- Are effect sizes and confidence intervals reported per APA 7th?
- Are statistical assumptions checked and reported?
- Are results over-interpreted or under-interpreted?
- Are non-significant findings handled appropriately, neither ignored nor over-explained?
- Do tables and figures effectively support the findings, or are any superfluous? (Wiley)
- Are labels, titles, and statistical notation clear? (Wiley)

#### Discussion

- Are interpretations supported by the results actually obtained? (Wiley: "conclusions should not be surprising")
- Are limitations acknowledged honestly and specifically?
- Are practical and theoretical implications distinct? (APA)
- Are future directions specific, not generic ("future research should explore...")?
- Does the discussion return to the theoretical framework established in the introduction?
- Does it address gaps and inconsistencies in the findings? (Wiley)

#### References

- Do references adequately support the manuscript's claims?
- Are significant similar or opposing studies missing?
- Is the reference list current, well-balanced, and not over-reliant on self-citation? (Wiley)
- Are references retrievable and in APA 7th format?

#### For dissertation proposals specifically

- Is the proposed contribution to the field clear and novel?
- Is the proposed method feasible given available resources and timeline?
- Does the proposal demonstrate command of the relevant literature?
- Are the research questions answerable with the proposed design?

---

### Synthesis: Cross-cutting assessment

*Per Wiley Step 6 and APA report structure.*

- **Thread coherence:** Do research questions flow through method → results → discussion as a connected argument? Identify any breaks.
- **Internal consistency:** Are claims in the discussion supported by the results? Are key terms used consistently throughout?
- **Writing quality:** Flag paragraph-level coherence issues, jargon overuse, and passive voice density. Do not copy-edit, copyediting is separate from review (APA/Wiley).
- **APA format compliance:** Spot-check headings, citation style, table/figure formatting. Exhaustive reference format checking is the editor's role (Wiley).
- **EDI considerations (APA):** Does the manuscript use bias-free language? Are participant samples described with inclusion efforts explained? Could any framing harm or stigmatize vulnerable populations? (Reference: APA Bias-Free Language Guidelines)

---

## Output format

*Aligned with Wiley Step 6 and APA narrative structure. Lead with positives (Wiley). Major concerns 5–10 items; minor concerns 10–20 items (APA). All points numbered with section and page references.*

---

**Summary**

[2–3 sentences stating what the manuscript does and what it finds. Then: key strengths, what it does well. Wiley: give positive feedback first so authors engage with the review.]

---

**Dimension Ratings**

Rate each dimension: **Strong** / **Adequate** / **Needs Strengthening**, with a one-line justification. (APA review form dimensions)

| Dimension | Rating | Justification |
|---|---|---|
| Significance of the issue addressed | | |
| Contribution of new knowledge to the field | | |
| Quality of research design and analysis | | |
| Adequacy of the data | | |
| Quality of data interpretation | | |
| Coverage and relevance of literature reviewed | | |
| Quality of writing (clarity, organization, style) | | |
| Utility of tables and figures | | |

---

**Major Concerns**

[Numbered list, 5–10 items. Each concern: state the issue, the section and page where it occurs, and a question for the author. Focus on deficiencies in science, not writing (APA). These are issues that would require substantial revision before the work is ready for submission.]

1. [Section, p. X] …

---

**Minor Concerns**

[Numbered list, 10–20 items. Cite section headings and specific page/paragraph numbers (APA). Includes writing clarity, formatting, presentation, and reference issues.]

1. [Section, p. X] …

---

**Questions for the Author**

[Numbered list. Genuine questions probing unclear reasoning, gaps in argument, or missing justification. These push back as a reviewer would, not rhetorical, but substantive.]

1. …

---

**Thread Coherence**

[Brief assessment of whether the RQ → theory → method → results → discussion chain holds together. Identify specific breaks and where the thread becomes unclear.]

---

**Overall Impression**

[2–3 sentences on the manuscript's contribution, its readiness, and where effort should be focused. No accept/reject recommendation, the reviewer evaluates; the editor decides (APA). Frame constructively: "Addressing X and Y would substantially strengthen this manuscript for submission."]

---

**File output:** Write the completed review to `peer-review-<manuscript-stem>-<YYYY-MM-DD>.md` in the current working directory. Print only the file path to terminal, not the full review.

---

## Hard limits

- Max 20 pages per Read call (tool constraint). Read full manuscripts in passes: pages 1–15, then 16–30, etc.
- Do not rewrite content. Flag the issue and ask a question. (Wiley/APA)
- Do not suggest specific citations to add. Note where coverage is thin and ask what literature the authors draw on.
- Citation integrity: follow `rules/citations.md`. Do not name specific papers as missing unless they are confirmed in the local catalog. State the gap without inventing the paper.
- Do not provide an accept/reject recommendation. (APA: "do not include your recommended decision within the narrative to the author")
- Treat multiple files as parts of the same manuscript, not independent papers.
- Critique within the author's theoretical framework, not from an external framework preference.
- Use third person throughout, "the authors," "the manuscript", never "you." (APA)
- Give positive feedback before criticism. (Wiley)
- Even if serious issues exist, identify what the manuscript does well. (Wiley)

---

## I-O Psychology and psychometrics guardrails

Apply these checks regardless of whether the manuscript explicitly addresses them:

- **Causal language:** Flag any causal claim from correlational data without acknowledged limitations
- **Construct validity:** Check that reliability, validity evidence, and factor structure are discussed for all primary measures
- **Common method bias:** Flag if survey-based studies do not address CMB
- **Level of analysis:** In multilevel studies, verify that the level of theory matches the level of analysis
- **Time lag justification:** In longitudinal studies, check that the measurement interval is theoretically grounded
- **Scale development:** If measures are developed or adapted, check against *Standards for Educational and Psychological Testing* (AERA, APA, NCME)
- **JARS compliance:** Apply quantitative JARS for quantitative studies; apply qualitative JARS per Levitt et al. (2017) for qualitative work

---

## Integration with other skills

**Rules take precedence over this skill.** If `rules/session.md` or other rule files conflict with a step below, the rule governs.

- **anaiis-litreview:** When a literature gap is identified, note it in Major or Minor Concerns and let the user invoke litreview separately. The reviewer identifies gaps; it does not do the search.
- **anaiis-agents:** For manuscripts over 50 pages, consider invoking the agents skill to parallelize the Read 2 section reviews (one agent per major section), then synthesize in the main thread.
- **anaiis-copyedit:** If the user wants copyediting after the peer review, that is a separate invocation. This skill flags issues; it does not rewrite.
