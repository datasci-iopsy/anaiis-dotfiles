#!/usr/bin/env bash
# Seed workspace for r-survey-means. Runs in the empty eval workspace before Claude starts.
set -eu
mkdir -p R data
cat >R/survey.R <<'EOF'
# Survey helpers.

read_survey <- function(path) {
  read.csv(path, stringsAsFactors = FALSE)
}

n_respondents <- function(path) {
  nrow(read_survey(path))
}
EOF
cat >data/responses.csv <<'EOF'
id,group,q1,q2,q3,q4,q5
1,a,4,5,3,NA,2
2,a,3,NA,4,4,1
3,b,5,5,5,5,5
4,b,NA,2,3,3,4
5,a,2,3,NA,4,3
6,b,4,4,4,NA,NA
EOF
git init -q
git add -A
git -c user.name=eval -c user.email=eval@local commit -q -m base
