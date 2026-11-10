#!/usr/bin/env bash
# Benchmark each optimization step and the thread scaling of the final one.
#
#   ./bench.sh [steps|threads|schedules|perfstat|all]   (default: all)
#
#   steps      build every commit in STEPS with its own Makefile and time it
#   threads    time HEAD with each thread count in THREADS
#   schedules  time HEAD with each OMP_SCHEDULE in SCHEDULES
#              (only if sandpile.c uses schedule(runtime))
#   perfstat   one `perf stat` run of every commit in STEPS; appends cycles,
#              instructions, branches, branch and cache misses to
#              results/perfstat.csv (not part of `all`)
#
# Environment overrides:
#   N=1001               grid size
#   REPS=1               runs per configuration
#   THREADS="1 2 4"      thread counts for `threads` (default: powers of two
#                        up to the number of physical cores, plus that number)
#   STEP_THREADS=<cores> threads for OpenMP builds in `steps` and `schedules`
#
# Every run's identity.png is compared with identity-ref.png (N=1001) or with
# the first step's output (other N). Results are appended to results/bench.csv.
set -euo pipefail
cd "$(dirname "$0")"

# Optimization steps, oldest first: "<commit>|<label>".
STEPS=(
  "15fe837|original"
  "e898c81|hoist loop invariants"
  "87a9fc4|per-row disk bounds"
  "814ce2e|OpenMP 3-phase rows"
)
SCHEDULES=("static" "static,1" "static,8" "dynamic,4" "guided")

MODE=${1:-all}
N=${N:-1001}
REPS=${REPS:-1}
CORES=$(lscpu -p=core,socket | grep -v '^#' | sort -u | wc -l)
STEP_THREADS=${STEP_THREADS:-$CORES}
if [ -z "${THREADS:-}" ]; then
  THREADS=""
  for ((t = 1; t < CORES; t *= 2)); do THREADS+="$t "; done
  THREADS+="$CORES"
fi

work=$(mktemp -d)
cleanup() {
  for wt in "$work"/src-*; do
    [ -d "$wt" ] && git worktree remove --force "$wt" >/dev/null 2>&1
  done
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/run" results

# build <rev>: checks out <rev> in a worktree, runs its Makefile, prints the
# path of the resulting binary.
build() {
  local dir="$work/src-$1"
  if [ ! -x "$dir/sandpile.exe" ]; then
    git worktree add --detach -f "$dir" "$1" >/dev/null 2>&1
    make -s -C "$dir" all >/dev/null
  fi
  echo "$dir/sandpile.exe"
}

if [ "$N" = 1001 ]; then
  ref=$PWD/identity-ref.png
else
  ref=$work/ref.png
  first=$(build "${STEPS[0]%%|*}")
  (cd "$work/run" && "$first" "$N" >/dev/null && mv identity.png "$ref")
fi

TIMEFORMAT=%R
# run <mode> <label> <rev> <threads> <schedule>: times REPS runs of <rev>.
run() {
  local exe secs ok line
  exe=$(build "$3")
  for rep in $(seq 1 "$REPS"); do
    rm -f "$work/run/identity.png"
    secs=$( { time (cd "$work/run" && OMP_NUM_THREADS=$4 OMP_SCHEDULE=$5 \
                    "$exe" "$N" >/dev/null 2>&1); } 2>&1 )
    if cmp -s "$work/run/identity.png" "$ref"; then ok=OK; else ok=MISMATCH; fi
    line="$1,$2,$3,$4,$5,$N,$rep,$secs,$ok"
    echo "$line"
    echo "$line" >>results/bench.csv
  done
}

echo "# $(lscpu | sed -n 's/^Model name: *//p'), $CORES physical cores, $(nproc) logical CPUs"
[ "$MODE" = perfstat ] || echo "mode,label,commit,threads,schedule,N,rep,seconds,output"

# perfstat <label> <rev>: one `perf stat` run of <rev>, counters appended to
# results/perfstat.csv. Serial builds are recorded as 1 thread.
perfstat() {
  local exe secs threads=1 counters out=$work/perf.csv
  exe=$(build "$2")
  git show "$2:Makefile" | grep -q -- -fopenmp && threads=$STEP_THREADS
  rm -f "$work/run/identity.png"
  secs=$( { time (cd "$work/run" && OMP_NUM_THREADS=$threads perf stat -x, -o "$out" \
                  -e cycles,instructions,branches,branch-misses,cache-misses \
                  "$exe" "$N" >/dev/null 2>&1); } 2>&1 )
  if ! cmp -s "$work/run/identity.png" "$ref"; then
    echo "# output mismatch for $1, not recorded" >&2
    return
  fi
  # perf -x, lines are "value,unit,event[:modifiers],..."
  counters=$(awk -F, '{ split($3, e, ":"); if (e[1] == "cpu-cycles") e[1] = "cycles"; v[e[1]] = $1 }
    END { printf "%s,%s,%s,%s,%s", v["cycles"], v["instructions"], v["branches"],
          v["branch-misses"], v["cache-misses"] }' "$out")
  [ -f results/perfstat.csv ] ||
    echo "label,commit,threads,seconds,cycles,instructions,branches,branch_misses,cache_misses" \
      >results/perfstat.csv
  echo "$1,$2,$threads,$secs,$counters" | tee -a results/perfstat.csv
}

if [ "$MODE" = perfstat ]; then
  echo "label,commit,threads,seconds,cycles,instructions,branches,branch_misses,cache_misses"
  for step in "${STEPS[@]}"; do
    perfstat "${step#*|}" "${step%%|*}"
  done
fi

if [ "$MODE" = steps ] || [ "$MODE" = all ]; then
  for step in "${STEPS[@]}"; do
    run steps "${step#*|}" "${step%%|*}" "$STEP_THREADS" ""
  done
fi

if [ "$MODE" = threads ] || [ "$MODE" = all ]; then
  for t in $THREADS; do
    run threads "HEAD" "$(git rev-parse --short HEAD)" "$t" ""
  done
fi

if [ "$MODE" = schedules ] || [ "$MODE" = all ]; then
  if git show HEAD:sandpile.c | grep -q 'schedule(runtime)'; then
    for s in "${SCHEDULES[@]}"; do
      run schedules "HEAD" "$(git rev-parse --short HEAD)" "$STEP_THREADS" "$s"
    done
  else
    echo "# skipping schedules: HEAD's sandpile.c does not use schedule(runtime)" >&2
  fi
fi
