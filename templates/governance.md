# AI-Craftman governance policy

<!-- Read by the governance and human-oversight agents. Edit to match your organisation. -->

autonomy: medium            # low = approve every gate | medium = risk-based | high = only deploy/push/destroy/waivers
coverage_threshold: 80      # % line coverage required at the release gate
max_review_loops: 2         # review/fix loops before escalating to a human

## Required at every release
- Full test suite green; lint and typecheck clean
- No high/critical dependency vulnerabilities
- No secrets in code, config or logs
- Every acceptance criterion has a passing test
- Security review has no open critical/high findings

## Dependencies
- Allowed licenses: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC
- New dependencies need a justification in the design

## Data
- No PII in logs
- Schema migrations must be backward compatible for one release

## Project-specific rules
<!-- e.g. "All public APIs are versioned under /v{n}", "Payments code needs two approvals" -->
