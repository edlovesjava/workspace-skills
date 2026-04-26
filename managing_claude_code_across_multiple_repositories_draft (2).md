# Managing Claude Code Across Multiple Repositories

## Draft for Final Edits and Review

---

## Introduction

Most modern advice for agentic coding assumes a clean world: a single repository, a unified build, and a tidy boundary around your system.

That’s not the world many of us actually live in.

Instead, we have years of history using multiple repositories for related aspects of the same application or service:

- A React client in one repo connecting to 
- A REST API in another leveraging 
- A shared model library (POJOs) or sdk for clients to access in a third, 
- End-to-end test harnesses in a forth repo providing system tests and 
- Flyway schemas and deployment scripts in a final repo to provide data 

each related to each other, where change must happen across multiple repositories rather than just one.

Each repository has a clear responsibility and tech stack. CI/CD pipelines are built around that separation. Changing that structure from multi repo to mono repo isn’t just technical—it’s organizational.

So while mono-repos may be “better” in theory, we still need a way to work effectively in a **multi-repo system**, especially when introducing **Claude Code and agentic workflows**.

Even if mono repos are used for related services, in a micro service/domain service world, change still may affect many distributed services at once. The case still exists, needing to change multiple repositories for a single feature or change.

---

## The Core Problem: Context Fragmentation

Claude (and agents in general) thrive on context.

In a multi-repo setup:

- Context is fragmented
- Dependencies are implicit
- Changes span multiple repos
- Documentation is scattered

Without structure, you get two failure modes:

1. The agent is too local → misses cross-repo implications
2. The agent is too global → becomes noisy and unfocused

The goal:

> Provide enough context to reason across repositories—without overwhelming the system.

Similarly, if context exists only in a local environment and isn't shared with others or persisted in systems not accessible easily to the coding agent. Similarly not preserved over time. Leading to the desire to version control information that may span across multiple repositories.

---

## Pattern 0: Refactor to a mono repo

At first glance, the most obvious solution to multi-repo complexity is to eliminate it entirely: consolidate everything into a single monorepo. And in many cases, that *is* a cleaner long-term architecture.

But in practice, large-scale refactoring of repository structures is one of the hardest changes to make in an organization. It impacts:

- CI/CD pipelines
- team ownership boundaries
- release processes
- access controls and compliance
- developer workflows and tooling

Historically, this kind of change has been expensive, slow, and risky—often requiring dedicated migration efforts that compete with feature delivery.

However, the introduction of Claude and other coding agents changes the equation.

> Large-scale, cross-cutting changes to codebases and supporting infrastructure are now far more plausible than they used to be.

Why?

- Agents can systematically analyze and update large numbers of files across repositories
- They can follow consistent transformation rules (renames, API changes, structural refactors)
- They can generate and update tests alongside code changes
- They can assist in updating build pipelines, configs, and deployment scripts
- They can work incrementally, validating each step rather than requiring a “big bang” migration

What used to be a multi-month coordinated effort across teams can now be approached as a series of smaller, verifiable transformations.

That doesn’t mean monorepos suddenly become easy or always the right choice. Organizational constraints, ownership models, and deployment independence still matter.

But it does mean this:

> Architectural changes that were once avoided because they were too disruptive are now back on the table.

Even if you don’t choose to move to a monorepo, this shift is important. The same capabilities that make large refactors possible also make it easier to coordinate change across multiple repositories— which is what the rest of this article focuses on.

### References and Example Monorepo

For readers exploring monorepo approaches, these are useful perspectives:

- Martin Fowler (balanced trade-offs): [https://martinfowler.com/articles/monorepo.html](https://martinfowler.com/articles/monorepo.html)
- Bazel / Google concepts (large-scale view): [https://bazel.build/concepts/monorepo](https://bazel.build/concepts/monorepo)
- Nx (practical developer workflow): [https://nx.dev/concepts/why-monorepos](https://nx.dev/concepts/why-monorepos)
- Turborepo docs (modern pragmatic tooling): [https://turbo.build/repo/docs](https://turbo.build/repo/docs)

A small sample monorepo you can explore:

- [https://github.com/edlovesjava/sample-mono-repo](https://github.com/edlovesjava/sample-mono-repo)

A typical mono repo layout for our earlier example might look like:

```
monorepo/
  ├── apps/
  │     ├── profile-ui/
  │     └── profile-api/
  ├── libs/
  │     └── profile-sdk/
  ├── db/
  │     └── migrations/
  └── e2e/
        └── profile-tests/
```

In a monorepo, this structure exists physically. In the approach described in this article, we recreate a similar *logical structure dynamically* using workspaces and agent coordination.



## Pattern 1: Introduce a Root Workspace Project

### What we mean by "workspace"

Throughout this article, **workspace** is used as a *generic* term:

> A root directory where a coherent unit of work is performed.

A workspace can take several forms:

- a simple parent folder containing multiple cloned repositories
- a mono repo with multiple modules
- a root repository that references others via submodules
- a directory structure that groups Git worktrees across repositories

The key idea is not the mechanism, but the **scope of context**: a workspace represents *all components needed to reason about and implement a change*.

Create a **logical monorepo** without restructuring your system.

Create a **logical monorepo** without restructuring your system.

A root project:

- References all related repositories (submodules or directories)
- Represents a single domain service
- Provides shared context for Claude

This becomes the **unit of reasoning**.

Using submodules in git means that the root workspace can become a first class repository in itself, and become a source for rules and skills, or documentation or other cross cutting scripts, while maintaining separate repositories for the constituent components, particularly if versioned or managed separately. UI teams may own the front end, infra the CI/CD and configurations, QA the end to end tests, and feature teams the services encompassing the business rules and functionality.

- Git submodules: [https://git-scm.com/docs/git-submodule](https://git-scm.com/docs/git-submodule) 

---

## Pattern 2: Scope Rules at the Right Level

Three effective scopes:

### Repository-Level

the repository for the service API is separate from the client that accesses it, or the db schema that supports it or the end to end automated tests that verify it. Each are different tech stacks and concerns even though related. What can be unique to the repository would be:

- Coding standards
- Build/test commands
- Local architecture

### Workspace-Level

The 'workspace' level is the grouping of repositories supporting typically a domain service partition, inclusive of front end, back end, data and infrastructure components that share common context.

This level common context can be

- Overall purpose
- Domain context
- Component interaction
- API contracts
- Integration rules

### Task/feature-Level

This level focuses on the information for a feature being implemented, typically providing context specific to the often end-to-end feature that may encompasses changes in the front end, the back end, the data and infrastruture, and tests. This information can reside in the issue management system or product requirements documents but needs to be accessible to the agent when working on that task, and not muddle context when agents work on other tasks or other scopes.

- Feature-specific intent
- Temporary constraints
- Acceptance criteria
- Success measurements
- Plans and progress tracking

> Avoid overly global rules—they degrade agent performance.

---

## Pattern 3: Worktrees as the Unit of Change (Parallel Workspaces)

### What is a Git worktree?

A Git worktree allows you to have **multiple working directories attached to the same repository**, each checked out to a different branch.

- Official docs: [https://git-scm.com/docs/git-worktree](https://git-scm.com/docs/git-worktree)

Instead of constantly switching branches (and stashing or committing partial work), worktrees let you:

- keep multiple branches active at the same time
- isolate changes per branch
- avoid context switching overhead

In this article, we combine that idea with the broader concept of a **workspace**:

> A workspace is the root directory grouping all repositories (or worktrees) needed for a specific unit of work, while a worktree is a Git mechanism used to support multiple parallel branches within each repository.

Use **branch-based workspaces**, not just repository branches.

> One workspace per branch (typically a Jira ID)

```
workspace/
  ├── ABC-1234-feature-x/
  │     ├── client/
  │     ├── api/
  │     ├── model/
  │     ├── tests/
  │     └── db/
  │
  ├── ABC-1201-hotfix/
  │     ├── client/
  │     ├── api/
  │     └── db/
```

Benefits:

- Parallel work streams (dev, review, validation, hotfix)
- Cross-repo consistency
- Clean, isolated agent context

Often we work on multiple things at once. Having to switch contexts sometimes means stashing changes, or committing artificially posisibly half finished code to check out another branch and do a more urgent task. In more effeicient workflows one can work on design of one thing, development of another, validation/testing or fixing of a third, all sharing the same repositories. This is exactly the case for git worktrees.

- Git worktrees: [https://git-scm.com/docs/git-worktree](https://git-scm.com/docs/git-worktree)

Although one can create worktrees located near the repository, another organization can help provide grouping around the branch or feature where multiple repositories are touched.

---

## Pattern 4: Agent-Assisted Workspace Management

Building on the above patterns, managing multi-repo workspaces manually is tedious and error-prone.

Define **skills** to encapsulate operations:

- `workspace:init <jira-id>`
- `workspace:sync <jira-id>`
- `workspace:exec <jira-id>`
- `workspace:teardown <jira-id>`

These handle:

- Creating root workspace
- Attaching repositories
- Checking out branches
- Rebasing and syncing
- Running cross-repo tasks

---

### Claude as Orchestrator

Claude coordinates rather than executes:

- Interprets intent
- Selects skills
- Delegates execution
- Validates results

---

### Sub-Agent Model

Use layered agents:

- Primary agent: reasoning and planning
- Sub-agents: procedural execution

This improves efficiency and reliability.

---

### Useful Skills to Share

What makes this pattern practical is not just the workspace structure, but the **capability layer** around it.

At the top level, Claude can use a small set of generic workspace skills. Those skills can then delegate to lower-level skills or tools that handle the mechanical work.

For example:

#### Workspace Skills

- `workspace:init <jira-id>`\
  Create the root workspace, attach repositories, create or check out worktrees, fetch latest, and align branches.

- `workspace:status <jira-id>`\
  Summarize repository branch state, local changes, outstanding commits, pull request links, CI status, and deployment state.

- `workspace:sync <jira-id>`\
  Rebase or merge latest changes, refresh submodules or directory mappings, and validate that the workspace is still coherent.

- `workspace:test <jira-id>`\
  Run the right mix of unit, integration, REST, UI, and end-to-end tests across the affected repositories.

- `workspace:teardown <jira-id>`\
  Clean up worktrees and temporary workspace structure once the work is complete.

These skills stay intentionally generic. They express the developer’s intent at the workspace level.

Underneath, they can delegate to more specialized capabilities.

#### Lower-Level Capability Abstractions

A useful refinement is to keep even the lower layer **tool-agnostic**.

Instead of binding directly to specific tools, define skills around **capabilities**:

- **Version Control (VCS)**\
  Abstracts repository operations: branching, diffing, PR status, history.\
  *Implementation examples: ********************************************************************************************************************************************************************************gh********************************************************************************************************************************************************************************, Git CLI*

- **Task Tracking**\
  Abstracts work items, status, acceptance criteria, and relationships.\
  *Implementation examples: Jira via Atlassian MCP, or direct user interaction*

- **CI/CD Pipeline**\
  Abstracts builds, test runs, pipeline status, and artifacts.\
  *Implementation examples: GitHub Actions, Jenkins*

- **Infrastructure / Runtime Operations**\
  Abstracts deployment state, rollout status, environment health.\
  *Implementation examples: Kubernetes MCP*

- **Monitoring / Observability**\
  Abstracts logs, metrics, alerts, and system health signals.\
  *Implementation examples: Kubernetes, Datadog*

The key idea is that Claude interacts with **stable capability interfaces**, not specific tools.

This gives you flexibility:

- swap GitHub Actions for Jenkins without changing workspace logic
- add Datadog later without redesigning skills
- evolve infrastructure without retraining the agent’s mental model

That also means the capability set can evolve over time:

- start with shell scripts and `gh` commands
- later add MCP integrations for Jira, Jenkins, or Kubernetes
- keep the top-level workflow stable even as implementation improves

---

### Example Skill Flow

A realistic interaction might look like this:

> Start work on `PROF-1042`, sync the related repos, and tell me whether CI and the validation environment are healthy.

Claude can then:

1. call `workspace:init PROF-1042`
2. inspect repo state and worktree alignment
3. use GitHub tooling to check open pull requests and Actions results
4. use Jira tooling to summarize the work item and acceptance criteria
5. use Kubernetes tooling to check the validation namespace
6. return a concise workspace-level status summary

That is much more useful than a pile of individual command output. It turns procedural tool execution into an agent-friendly workflow.

---

### Outcome

You create a **control plane** for your system:

- Repositories stay independent
- CI/CD remains unchanged
- Development becomes coordinated

---

## Example: A Small Multi-Repo Service

To make this more concrete without exposing proprietary details, it helps to use a realistic but contrived example.

Imagine a simple customer profile service split across multiple repositories:

- `profile-ui` — a React client
- `profile-api` — a REST backend
- `profile-sdk` — a shared client/library and model package
- `profile-db` — Flyway schema and seed data
- `profile-e2e` — end-to-end tests using REST Assured and Selenide

This is not unusual. Many organizations arrived at a structure like this over time:

- UI separated from backend delivery cadence
- Shared contracts published independently
- Database evolution managed in its own lifecycle
- Test harnesses maintained separately from production code

Now imagine a Jira story:

> `PROF-1042 Add preferred display name to customer profile`

That single change may require:

- database migration for the new column
- backend API updates
- SDK/model changes
- UI form and display updates
- new REST and browser-based end-to-end tests

This is exactly the kind of work that looks simple in a ticket but spans multiple repositories in practice.

A branch-grouped workspace for that work might look like:

```
workspace/
  └── PROF-1042-display-name/
        ├── profile-ui/
        ├── profile-api/
        ├── profile-sdk/
        ├── profile-db/
        └── profile-e2e/
```

The value of the workspace is that Claude can reason about the change as one coherent task rather than five disconnected repositories.

You can then scope documentation and rules appropriately:

- repo-level guidance inside each repository
- workspace-level guidance at the root for cross-repo concerns
- task-level instructions tied to the Jira item

For example, a workspace-level note might say:

> When profile fields change, update schema, API contract, SDK models, UI rendering, and both REST and browser-based end-to-end validation.

That kind of guidance is too broad for a single repository and too specific to leave undocumented.

You can also imagine a skill-driven workflow like this:

1. Initialize workspace for `PROF-1042`
2. Create or sync worktrees across all relevant repositories
3. Rebase on latest main branches
4. Apply repo-specific rules where needed
5. Run affected test suites across repositories
6. Tear down workspace when the work is complete

Even in a simplified example, the value becomes obvious: the hard part is not writing one class or one screen. The hard part is coordinating a consistent change across a system that is physically separated into multiple repos.

---

## Pattern 5: Documentation That Matches Reality

Split documentation intentionally:

### Repository-Level

- Build instructions
- Internal structure

### Workspace-Level

- Service architecture
- Data flow
- API contracts

> Some documentation belongs above the repo level.

---

## Pattern 6: Guide Claude with Focused Context

Provide only relevant context per task:

- Identify affected components
- Limit scope intentionally

This improves signal and output quality.

---

## Pattern 7: Align CI/CD with Cross-Repo Work

Bridge repo-centric pipelines with system-level work:

- Trigger downstream builds
- Run integration pipelines
- Validate contracts

---

## Final Thought

This approach doesn’t replace your architecture.

It creates a layer above it:

> A structured environment where humans and agents can reason about the system as a whole.

The biggest shift in agentic development isn’t how code is written.

It’s how context is organized.

And ultimately:

> Agents shouldn’t learn your tools—they should learn your system’s capabilities.

---

## Notes for Review

- Consider adding real examples of skills implementation
- Optionally tie into Spec-Driven Development
- Could include diagram of workspace structure
- Add links/references if publishing externally

