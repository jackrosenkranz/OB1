# Tooling

Read this only when the user asks what to install. Nothing here is required to
get a first number.

## The honest starting position

A general coding agent, a folder of eval tasks in plain files, and a pinned
judge is a legitimate stack. Blind evaluations of production traces have put
general coding agents in the same recall band as dedicated evaluation
platforms — close enough that nobody should wait on procurement to measure
their agent for the first time.

Several evaluation vendors now ship their own expertise as skills installed
into a coding agent rather than as a separate product, which tells you where
the floor is.

## What to install, if anything

Two distinct jobs, and people usually install for the first and then wonder
where the material comes from:

- **Building evals** — the rubric, task, and harness authoring layer.
- **Pulling real runs** — trace access to build those evals *from*. Without
  this, everything gets built from imagination, which is the failure mode the
  whole discipline exists to fix.

Get trace access working first. It is the scarce input.

## Vendor packages

Several vendors publish installable eval skill packs and CLI kits (LangChain,
Galileo, AWS, and Arize have all shipped in this shape, some under permissive
licenses). Most follow the open skills specification, so the same files load
into more than one client.

Before recommending any specific install command:

1. Check the vendor's current documentation for the package name and install
   syntax — these move fast and commands from a blog post go stale within
   weeks.
2. Check the license against this repo's FSL-1.1-MIT terms if the output will
   be redistributed.
3. Prefer packages that read your traces over packages that generate test cases
   for you.

Do not paste an install command into a user's terminal from memory. Look it up,
or tell them what to search for.

## A typical phased kit

The CLI kits that exist tend to share a shape, each phase writing into an
`eval/` folder the next one reads:

```
init      -> scaffold the eval folder
plan      -> decide what capability is under test
data      -> assemble the case set
trace     -> pull real runs
run       -> execute the agent against the cases
eval      -> score them
report    -> prioritized recommendations pointing at specific code locations
```

The last phase is the one worth the setup. A report that names a file and a
line is a fix; a report that names a percentage is a feeling.

If no kit fits, this sequence works by hand — it is just seven folders and a
script.

## Open Brain as the durable layer

Whatever tool runs the suite, the failure log belongs in Open Brain rather than
in the vendor's database:

- the failure, its attribution, and the eval that guards it
- the rubric line and the judge version in force at the time
- the date, so a re-appearance is detectable

Tools get swapped. The failure log is what makes the next tool useful on day
one.
