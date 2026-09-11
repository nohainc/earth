# EARTH Technology, Research & IP V2

> **Building tiers define what a building is. Technologies define how efficiently a corporation operates. Patents temporarily control who may access selected breakthrough technologies, and licenses transfer that access between corporations for explicit Economy V2 payments.**

Technology definitions live in `technology_catalog`. Research is represented by
`corporation_research_projects`, access is resolved by the canonical corporation
technology resolver, and modifiers are consumed from the compact corporation-day
projection. Patents, licenses, research completion, and public-domain transitions
are effective on explicit game-day boundaries.

Research funding and license payments use Economy V2 posting primitives. The
research and IP tables describe contracts, rights, and audit state; they are not
alternative balance authorities.

The acceptance suite is split between lifecycle scenarios, modifier properties,
and target-scale projection checks:

```text
test/technology-ip-v2.scenarios.test.mjs
test/technology-modifier-properties.test.mjs
test/technology-scale.test.mjs
```
