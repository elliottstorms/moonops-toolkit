# Provenance manifest

Manifest date: 2026-07-20.

This file timestamps the existence of private work without exposing any of it.
Each entry binds this public, dated repository to the exact state of a private
source tree at a moment in time: the commit SHA names one specific commit, and
the tree hash (`git rev-parse HEAD^{tree}`) is a cryptographic digest of the
entire contents of that commit's tree. The hashes reveal nothing about the
trees themselves, and nothing about them can be reconstructed from this file.

The point is verifiability after the fact. If it ever matters, the private
repository can be revealed and re-hashed: check out the named commit, run
`git rev-parse HEAD^{tree}`, and the value must match what is published here.
Because a matching hash can only come from the exact tree it describes, a
match proves the work existed in precisely this form on or before the date
this manifest was committed to the public record.

| Repository | HEAD commit | Tree hash (`HEAD^{tree}`) | Last commit date |
|---|---|---|---|
| moonops | `cd964a38f0c3b0fb015f09b906919667edcf52c9` | `c005536200fcf3d36869996a6fcd593ccbd5442d` | 2026-07-20 |
| mission-control | `0e48e69e60cdae4ac9544d0cee2f89d2f16f9fd4` | `593559e912fc7a111a37b6cd6ff195ccc0d950b1` | 2026-07-20 |
| private-venture-01 (name withheld) | `4d4ee6855720e2a87767ea00ff37cb8befe95e39` | `217ec4ab78085ca10e6ebed54e62af85a55401de` | 2026-07-10 |
