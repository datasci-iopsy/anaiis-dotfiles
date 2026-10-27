---
type: regex
pattern: "PONYTAIL MODE ACTIVE"
target: trace
arm: with-only
---
Plugin-fired indicator: the SessionStart hook's ruleset header is present in this run's transcript. Scored in the with-arm only; a without-arm run that matched would mean the arms are not isolated.
