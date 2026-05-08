---
name: citations
description: Citation integrity for specific paper claims (author, year, title, finding); does not restrict general conceptual or coding answers
---

# Citation Integrity

## What this rule covers

A citation is a specific claim about a paper: author name, year, title, journal, finding, or statistic attributed to a source. This rule governs how those claims are sourced, flagged, and formatted for traceability.

This rule does NOT restrict:
- Conceptual explanations of theories or models from training knowledge
- General characterizations of a research area ("research on burnout generally suggests...")
- Answering questions that do not require citing a specific paper
- Everyday coding, data, methodological, or general knowledge questions

## Citation sources and behavior

| Source | Behavior |
|---|---|
| Catalog-confirmed (DuckDB query or direct Read) | Cite normally. Include DOI/ISBN if present in catalog. |
| User-provided text in the conversation | Cite normally. No flag. |
| Training knowledge, paper likely real, not in local catalog | Answer substantively. Flag: "Not in your local catalog, drawing on training knowledge." Offer web search to confirm DOI. |
| Web search result | Cite with DOI (articles) or ISBN (books). If DOI/ISBN cannot be confirmed after searching, flag it. Never fabricate a DOI or ISBN. |
| Unknown provenance | Do not fabricate. State: "I don't have a confirmed source for this." |

## DOI and ISBN requirements

All citations that come from outside the local catalog, whether from web search or training knowledge, must include a DOI or ISBN when one exists:

- **DOI format:** `https://doi.org/10.xxxx/xxxxx`
- **ISBN format:** 13-digit ISBN-13 (e.g., 978-0-xxx-xxxxx-x)
- If a DOI/ISBN cannot be confirmed after searching: flag it explicitly, "Note: could not confirm a DOI for this paper. Verify before adding to your library."
- Never fabricate a DOI or ISBN. A hallucinated DOI resolves to the wrong paper or a dead link.
- Books: prefer ISBN-13 as the primary identifier. If a DOI also exists (e.g., book chapters in edited volumes), include both.
- Conference papers may have neither. Note what identifier is available; do not fabricate one.

## "My library / my corpus / my references" phrasing

When the user uses possessive language referring to their collection ("my library", "my body of work", "my references", "what do I have on X", "what's in my corpus"):

1. Search the local catalog first via DuckDB. This is the primary source.
2. Report what is found in the catalog.
3. If catalog results are thin (fewer than 5 relevant papers) OR the user signals interest in more ("what else is out there", "what am I missing", "are there more"), offer to expand with a web search.
4. Web results are supplementary, present them separately from catalog results and include DOIs/ISBNs.

This is a progressive pattern. Do not skip the local catalog when the user uses possessive phrasing. Do not limit the user to the local catalog when they ask for broader coverage.

## When a source is not in the local corpus

1. Answer substantively, do not refuse or withhold the conceptual response.
2. Flag the sourcing: "This paper is not in your local catalog. I'm drawing on training knowledge."
3. Offer a web search with DOI retrieval: "I can search the web for this and provide the DOI if you'd like to add it to your library."

## In research skills (litreview, peerreview)

Within formal research workflows:

- **litreview synthesis:** Cite only papers confirmed via catalog or direct Read in the primary synthesis. Web-expanded results appear in a separate "Expand your library" section with DOIs/ISBNs. See anaiis-litreview Step 6.
- **peerreview:** Note literature gaps without naming specific missing papers unless they are catalog-confirmed. Do not suggest "Author (Year) should be cited" if that paper is not in the catalog. When a gap is flagged, the user can invoke anaiis-litreview with web expansion to find trackable sources to fill it.
