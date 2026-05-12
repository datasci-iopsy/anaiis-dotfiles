---
name: citations
description: Citation integrity for specific paper claims (author, year, title, finding); does not restrict general conceptual or coding answers
---

# Citation Integrity

A citation is a specific claim about a paper: author name, year, title, journal, finding, or statistic. This rule governs sourcing, flagging, and formatting for traceability.

Not restricted: conceptual explanations, general research-area characterizations, questions that don't require citing a specific paper, coding/data/methodological answers.

## Citation sources

| Source | Behavior |
|---|---|
| Catalog-confirmed (DuckDB query or direct Read) | Cite normally. Include DOI/ISBN if present. |
| User-provided text | Cite normally. No flag. |
| Training knowledge, not in local catalog | Answer substantively. Flag: "Not in your local catalog, drawing on training knowledge." Offer web search to confirm DOI. |
| Web search result | Cite with DOI (articles) or ISBN (books). If DOI/ISBN unconfirmable, flag it. Never fabricate. |
| Unknown provenance | Do not fabricate. State: "I don't have a confirmed source for this." |

## DOI and ISBN requirements

- **DOI format:** `https://doi.org/10.xxxx/xxxxx`
- **ISBN format:** 13-digit ISBN-13
- If DOI/ISBN cannot be confirmed after searching, flag it: "Note: could not confirm a DOI for this paper. Verify before adding to your library."
- Never fabricate a DOI or ISBN.
- Books: prefer ISBN-13. Include DOI also if available (e.g., book chapters in edited volumes).
- Conference papers may have neither; note what identifier is available.

## "My library / my corpus / my references" phrasing

When the user uses possessive language about their collection:

1. Search the local catalog first via DuckDB.
2. Report what is found.
3. If catalog results are thin (fewer than 5 relevant papers) or the user signals interest in more, offer to expand with a web search.
4. Web results are supplementary; present them separately with DOIs/ISBNs.

## In research skills (litreview, peerreview)

- **litreview synthesis:** Cite only catalog-confirmed papers in the primary synthesis. Web-expanded results go in a separate "Expand your library" section with DOIs/ISBNs. See anaiis-litreview Step 6.
- **peerreview:** Note literature gaps without naming specific missing papers unless catalog-confirmed. Do not suggest "Author (Year) should be cited" if that paper is not in the catalog.
