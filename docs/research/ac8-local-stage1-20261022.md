# Local stage 1 — offline preparation, 2026-10-22

Scope: one stock guest F-14D in an isolated local world, keyboard/XInput input,
local-pose camera, explicit stop and retirement. No game launched. No original
installation or saves edited. This is preparation for an experiment, not a
runtime acceptance of flight or campaign co-op.

## Target and evidence

- Build 25201480, UE 5.4.3, x64 PE; preferred image base `0x140000000`.
- Offline EXE SHA256 `51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f`.
- GhidraMCP `get_program_info({})` confirms the offline target. Raw replies to
  `decompile_function_by_address` for `0x14793fde0` and `0x1478b9470` are saved
  in `evidence/local-stage1-20261022/`; parameters are embedded in each file.
- Existing `evidence/architecture-audit-20261022/candidate-byte-check.json`
  contains exact PE bytes and Capstone instructions used below. No new native
  call addresses or guessed signatures introduced. All addresses here are
  preferred PE VAs, not runtime/ASLR addresses.
- UE4SS MCP is not exposed in this session. UE4SS runtime was not started.
  Ghidra 12.1.4 / UE4SS 3.0.1-1181 toolchain identity remains as recorded earlier.

## Hypotheses and limits

**L31-01 (from audit A31-02):** the original sound preflight omitted a pointer
chain dereferenced by the player initializer. Criterion: exact instructions in
`147d4af60`, before call `1478b9470`. Confirmed statically:
`147d4be2d: 488b8608090000`, `147d4be3d: 488b8010020000`,
`147d4be44: 488b9040010000` read GI+908 -> manager+210 -> settings+140.
Subsequent instructions form FName pointers at +1c8 and +1d0/+1d8.
`owner_sound_readiness.h` checks these links/readability plus the previous
manager+1a8 registry; GI/manager use serial identities. Opaque child pointers
are NOT treated as UObjects, and name IDs are not invented. The guard runs
before creation, before Finish and during local steps. Missing objects prevent
allocation; bounded preflight permits asynchronous initialization to finish.

**L31-02:** these checks guarantee every internal prerequisite. **Not established.**
The saved decompile of `14793fde0` follows object/world to GI and then looks up
a class-keyed subsystem collection (+108/+100). It can return zero. This is
not evidence of a simple field getter or a safe new call ABI. No direct call
or guessed pointer patch was added. The sound wrapper `1478b9470` uses a sound
singleton and converts names; pointer-chain readability alone cannot prove all
audio internals, names or loaded assets are semantically valid. Further live
evidence or static producer analysis may still be needed after a refused test.

**L31-03:** local aircraft updates do not need round-trip echo before camera
movement. Offline contract tests confirm fixed-step-before-publish ordering,
send-failure independence, local pose consumption by the camera, sequence and
generation rejection. The actual native flight model has not executed here.

**L31-04:** cleanup must never declare success on a mere Destroy request.
Existing native ledger waits for actor, Parts, Network, children and captured
camera serial retirement. Fixed the pre-allocation branch to wait for a captured
camera even if full configuration failed. Lua revokes input before stopping
camera/provider, keeps polling receipts and requests GC at most once/second.
Exceptions or a 30-second deadline become `cleanup_unconfirmed`, with no retry
of creation in that process. Fake-memory/lifecycle tests cover the contract;
real EndPlay/GC order remains unverified.

## Prepared profile

`scripts/package_steam_coop.py --revision r31 --local-stage1` creates a separate
profile and ZIP; the published cinema-2 archive is not replaced. Manifest and
PE-export checks require the stage-1 dependencies, monotonic clock and preflight
exports. The kit's README is the local-test instruction, not the lobby guide.

Preparation waits up to 120 seconds for the isolated world and 45 seconds for
dependencies/initial state. F10 pauses local stepping; F9 stops the experiment.
Two seconds without camera updates or five seconds without fresh local pose
trigger cleanup. The test is fixed to mission 6 terrain, stock F-14D, collisions
disabled, other world simulation paused. No friend, Steam lobby or cinematic
barrier is needed. Steam may still be required by the installed game itself.

`owner-lab-status.tsv` records phase, dependency reason, input/model/camera/pose
counters and cleanup. It deliberately records `NOT_ACCEPTED_AUTOMATICALLY`.
Report collection already includes TSV/JSONL/AC8P files under session/mod.
Detailed autonomous results and artifact hashes are in MODLOG.md and the
evidence manifest. The next acceptance is the user-authorized one-game test
described in `coop/LOCAL-MODEL-TEST-RU.md`; two-PC flight remains a later gate.
