#!/usr/bin/env bash

# Tests script for checking map.lua (style mapping) consistency.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PARENT_DIR=$(dirname "$SCRIPT_DIR")

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

passed=0
failed=0
total=0

# Helper for running tests with nicer output
run_test() {
    local name="$1"
    local cmd="$2"
    ((total++))
    echo -e "${BLUE}▶ Running test:${NC} ${name}"

    if eval "$cmd"; then
        echo -e "${GREEN}✔ ${name} passed${NC}\n"
        ((passed++))
    else
        echo -e "${RED}✘ ${name} failed${NC}\n"
        ((failed++))
    fi
}

# TEST 1: Synthetic test to cover edge cases and such.
run_test "Synthetic style mapping, main test file" \
    "time diff -s --color=auto \
        ${SCRIPT_DIR}/test.output \
        <(pandoc -f markdown ${SCRIPT_DIR}/test.md -t markdown \
        --lua-filter=${PARENT_DIR}/map.lua -M map=${SCRIPT_DIR}/test.json --verbose)"

# TEST 2: Synthetic test to cover edge cases and such.
run_test "Synthetic style mapping, merge and join operators" \
    "time diff -s --color=auto \
        ${SCRIPT_DIR}/merge_and_join.output \
        <(pandoc -f markdown ${SCRIPT_DIR}/merge_and_join.md -t markdown_phpextra \
        --lua-filter=${PARENT_DIR}/merge.lua --verbose --wrap=none)"

# TEST 2B: Synthetic test to cover edge cases and such.
run_test "Synthetic style mapping, merge and join operators" \
    "time diff -s --color=auto \
        ${SCRIPT_DIR}/merge_and_join.output \
        <(pandoc -f markdown ${SCRIPT_DIR}/merge_and_join.md -t markdown_phpextra \
        --lua-filter=${PARENT_DIR}/merge_top_level_elements.lua --verbose --wrap=none)"

# TEST 3: Déborder Bolloré
# bollo.dbk was obtained with the following command:
# python -m idml2docbook -tlg -o lua-filters/tests/bollo.dbk -x idml2hubxml/Deborder-Bollore_140_205_250521_modifie.xml \ 
# --raster "jpg" --vector "svg" -f "images"
run_test "Déborder Bolloré (DocBook → Markdown)" \
    "time diff -s --color=auto \
        ${SCRIPT_DIR}/bollo.output \
        <(pandoc -f docbook ${SCRIPT_DIR}/bollo.dbk -t markdown_phpextra \
        --lua-filter=${PARENT_DIR}/roles-to-classes.lua \
        --lua-filter=${PARENT_DIR}/collapse-sections-into-headers.lua \
        --lua-filter=${PARENT_DIR}/map.lua \
        -M map=${SCRIPT_DIR}/bollo.json \
        --wrap=none --verbose)"

# Summary
echo -e "${YELLOW}─────────────${NC}"
echo -e "${BLUE}Test summary:${NC}"
echo -e "  Total:  $total"
echo -e "  Passed: ${GREEN}$passed${NC}"
echo -e "  Failed: ${RED}$failed${NC}"
echo -e "${YELLOW}─────────────${NC}"

if ((failed == 0)); then
    echo -e "${GREEN}✅ All tests passed successfully.${NC}"
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi
