#!/bin/bash
# ============================================================
# validate.sh - validate ablation output
#
#   usage:
#     bash scripts/validate.sh <NAME>     validate one config
#     bash scripts/validate.sh            validate all 11 configs
#
# Expected per family:
#   A1, A3      -> status=unavailable (no xdp_aggregator loader)
#   A2, A4,
#   A5-pkt*     -> status=ok, 8 latency rows, 1 scal row, CPU present
#   A6-w1       -> status=ok, 8 latency rows, 1 scal row, CPU present
#   A6-w2/4/8   -> status=ok, 0 latency rows (skipped), N scal rows,
#                  CPU skipped (single-client benchmark cannot trigger
#                  a grouped reply)
# ============================================================
cd "$(dirname "$0")/.."
ROOT=$(pwd)


validate_one() {
    local NAME=${1:-}
    [ -z "$NAME" ] && { echo "Usage: $0 <config>"; return 1; }

    local OUT="$ROOT/benchmarks/results/ablation/$NAME"
    if [ ! -d "$OUT" ]; then
        echo "=== Validation for $NAME ==="
        echo "  RESULT: FAILED - directory $OUT does not exist"
        return 1
    fi

    local META="$OUT/metadata.txt"
    local STATUS TYPE WORKERS
    STATUS=$(grep  '^status='  "$META" 2>/dev/null | cut -d= -f2)
    TYPE=$(grep    '^type='    "$META" 2>/dev/null | cut -d= -f2)
    WORKERS=$(grep '^workers=' "$META" 2>/dev/null | cut -d= -f2)
    WORKERS=${WORKERS:-1}

    local LAT_FILE="$OUT/latency_results.csv"
    local SCAL_FILE="$OUT/scalability_results.csv"
    local CPU_FILE="$OUT/cpu_results.txt"

    local LAT_ROWS LAT_FAIL SCAL_ROWS CPU_OK
    LAT_ROWS=$(grep -cE '^[0-9]' "$LAT_FILE"  2>/dev/null) || LAT_ROWS=0
    LAT_FAIL=$(grep -c 'FAIL'     "$LAT_FILE"  2>/dev/null) || LAT_FAIL=0
    SCAL_ROWS=$(grep -cE '^[0-9]' "$SCAL_FILE" 2>/dev/null) || SCAL_ROWS=0
    CPU_OK=0
    [ -s "$CPU_FILE" ] && grep -qE 'CPU Utilization|cpu median:' "$CPU_FILE" \
        && CPU_OK=1

    echo ""
    echo "=== Validation for $NAME ==="
    echo "  status:            $STATUS"
    echo "  type:              $TYPE"
    echo "  workers:           $WORKERS"
    echo "  latency rows:      $LAT_ROWS (fail: $LAT_FAIL)"
    echo "  scalability rows:  $SCAL_ROWS"
    echo "  cpu present:       $CPU_OK"

    local rc=0
    case "$NAME" in
        A1|A3)
            if [ "$STATUS" = "unavailable" ]; then
                echo "  RESULT: OK (correctly unavailable - no xdp_aggregator loader)"
            else
                echo "  RESULT: WARN - expected status=unavailable, got $STATUS"
                rc=1
            fi
            ;;

        A2|A4|A5-pkt16|A5-pkt32|A5-pkt64)
            [ "$STATUS" = "ok" ]   || { echo "  RESULT: FAILED - status=$STATUS";          rc=1; }
            [ "$LAT_ROWS" -ge 8 ]  || { echo "  RESULT: FAILED - latency rows < 8";       rc=1; }
            [ "$LAT_FAIL" -eq 0 ]  || { echo "  RESULT: FAILED - $LAT_FAIL latency FAIL"; rc=1; }
            [ "$SCAL_ROWS" -ge 1 ] || { echo "  RESULT: FAILED - no scalability rows";    rc=1; }
            [ "$CPU_OK" -eq 1 ]    || { echo "  RESULT: FAILED - no CPU measurement";     rc=1; }
            [ $rc -eq 0 ] && echo "  RESULT: OK"
            ;;

        A6-w1)
            [ "$STATUS" = "ok" ]   || { echo "  RESULT: FAILED - status=$STATUS";          rc=1; }
            [ "$LAT_ROWS" -ge 8 ]  || { echo "  RESULT: FAILED - latency rows < 8";       rc=1; }
            [ "$LAT_FAIL" -eq 0 ]  || { echo "  RESULT: FAILED - $LAT_FAIL latency FAIL"; rc=1; }
            [ "$SCAL_ROWS" -ge 1 ] || { echo "  RESULT: FAILED - no scalability rows";    rc=1; }
            [ "$CPU_OK" -eq 1 ]    || { echo "  RESULT: FAILED - no CPU measurement";     rc=1; }
            [ $rc -eq 0 ] && echo "  RESULT: OK"
            ;;

        A6-w2|A6-w4|A6-w8)
            local W=${NAME##*-w}
            [ "$STATUS" = "ok" ]      || { echo "  RESULT: FAILED - status=$STATUS";  rc=1; }
            [ "$SCAL_ROWS" -ge "$W" ] || { echo "  RESULT: FAILED - scal rows < $W";  rc=1; }
            [ $rc -eq 0 ] && echo "  RESULT: OK (latency + cpu skipped by design)"
            ;;

        *)
            echo "  RESULT: WARN - unknown config $NAME"
            rc=1
            ;;
    esac

    if [ $rc -ne 0 ]; then
        echo "  --- aggregator.log tail ---"
        tail -5 "$OUT/aggregator.log" 2>/dev/null | sed 's/^/    /'
        echo "  --- latency_results.csv head ---"
        head -3 "$OUT/latency_results.csv" 2>/dev/null | sed 's/^/    /'
        echo "  --- scalability_results.csv head ---"
        head -3 "$OUT/scalability_results.csv" 2>/dev/null | sed 's/^/    /'
        echo "  --- cpu_results.txt head ---"
        head -3 "$OUT/cpu_results.txt" 2>/dev/null | sed 's/^/    /'
    fi
    return $rc
}


validate_all() {
    local ORDER="A1 A2 A3 A4 A5-pkt16 A5-pkt32 A5-pkt64 A6-w1 A6-w2 A6-w4 A6-w8"
    local pass=0 fail=0 cfg
    for cfg in $ORDER; do
        if ( validate_one "$cfg" ) >/dev/null 2>&1; then
            printf '  [PASS] %s\n' "$cfg"; pass=$((pass+1))
        else
            printf '  [FAIL] %s\n' "$cfg"; fail=$((fail+1))
        fi
    done
    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}


NAME=${1:-}
if [ -z "$NAME" ]; then
    validate_all
else
    validate_one "$NAME"
fi