# CS598APE HW3

This repository contains code for homework 3 of CS598APE. It is relatively
simple in comparison to HW1 and HW2 to ensure you have enough time to work on
the course project. 

`sandpile.c` contains the implementation of finding the identity element of a 2D
abelian sandpile.

![Identity sandpile on a 1001x1001 pacman grid](identity-ref.png)

*Identity sandpile on a 1001x1001 pacman grid*


To compile the program, run:

```bash
make all
```

To clean existing build artifacts, run:

```bash
make clean
```

Usage (after compiling):

```bash
./sandpile.exe <N> 
```

where `N` is the grid size

Consider speeding up the generation of this 1001x1001 identity sandpile (which
takes approximately ~3m 40s on my local laptop under the default setup)

```bash
./sandpile.exe 1001
```

For an optional, ungraded challenge, see how large a sandpile you can compute
on the course VMs and report the grid size and runtime. There is no prescribed
upper limit on `N` for this challenge.


### Reproducing Benchmark and Verifying the Optimizations

#### Performance (the numbers in the report)

`bench.sh` reproduces every timing and counter in the report. For each
optimization commit it checks out a clean copy in a temporary git worktree,
builds it with that commit's own Makefile, runs `sandpile.exe 1001`, and
records the end-to-end time.

```bash
./bench.sh steps            # every optimization commit, ~25 min on the VM
REPS=3 ./bench.sh threads   # HEAD with 1, 2, 4 threads, ~18 min
./bench.sh perfstat         # one perf stat run per commit, ~25 min
```

Each run prints CSV and appends it to `results/`.

If `perf` reports a permission error, run
`sudo sysctl kernel.perf_event_paranoid=1` (resets on reboot).


#### Correctness (identical output)

`bench.sh` compares every run's `identity.png` byte-for-byte with
`identity-ref.png` and records `OK` or `MISMATCH` in the `output` column
(`perfstat` skips mismatching runs). Every run must say `OK`:

```bash
grep -c MISMATCH results/bench.csv
```

### Optimizations and How to Evaluate Individually

Each optimization is a single commit on top of the previous one. To measure
one in isolation, with `bench.sh` keep only those two lines in `STEPS`.

| # | Commit | Kind | Optimization | Time on VM |
|---|---|---|---|---|
| 0 | `15fe837` | | Baseline (single-threaded) | 652.2 s |
| 1 | `e898c81` | redundant work | Hoist loop invariants out of `stabilize`: `N`, `N/2` and `(N/2)^2` once per call, `(i-N/2)^2` and the row bound once per row | 384.5 s |
| 2 | `87a9fc4` | work reduction | Loop over each row's disk interval instead of testing every cell | 287.7 s |
| 3 | `814ce2e` | parallelism | OpenMP over rows in three phases (row mod 3) so that no two threads write the same cell | 91.2 s |
| 4 | `ba00791` | work reduction | Simulate only the upper half using the pacman's mirror symmetry (odd N; even N uses the full grid) | 60.0 s |

