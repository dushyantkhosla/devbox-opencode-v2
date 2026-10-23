---
description: Understand the core issue and assess whether the proposed solution is adequate or over-engineered. Use the `ponytail` skill and provide feedback. If there's a simpler, more efficient solution, propose that instead.
mode: subagent
model: opencode-go/glm-5.3-flash#max
steps: 50
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: allow
  - action: subagent
    resource: "*"
    effect: deny
---
