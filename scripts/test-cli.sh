#!/bin/sh
# Builds the calculum command and checks its output: results, quiet and JSON
# output, countries and units, choice inputs, and the error messages.
# Usage: scripts/test-cli.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
MACOS=$(sed -n 's/^ *macOS: *"\(.*\)"$/\1/p' project.yml | head -1)
mkdir -p build/test
swiftc -swift-version 6 -target "$(uname -m)-apple-macos$MACOS" -o build/test/calculum \
  CalculumCLI/main.swift Calculum/Engine.swift Calculum/Models.swift Calculum/NumberText.swift
export CALCULUM_ENGINE="$ROOT/Calculum/Resources/engine.js"
CLI=build/test/calculum
FAILED=0

expect() {
  name=$1 expected=$2
  shift 2
  actual=$("$CLI" "$@" 2>&1 || true)
  case "$actual" in
    *"$expected"*) echo "ok   $name" ;;
    *) echo "FAIL $name"; echo "     expected: $expected"; echo "     got: $actual"; FAILED=1 ;;
  esac
}

expect "calculates with the inputs given" '$2,078.11' mortgage-payment price=450000 rate=5.5 --country US -q
expect "shows every input and detail" 'Total interest     $382,118.79' mortgage-payment price=450000 rate=5.5 --country US
expect "prints JSON" '"value" : "$2,078.11"' mortgage-payment price=450000 rate=5.5 --country US --json
expect "reads Italian numbers and writes them the Italian way" '2253,52' mortgage-payment price=450.000 --country IT -q
expect "takes inputs in US units" '1.8 gal' paint-quantity perimeter=52.493 --country US -q
expect "accepts a choice by its label" '$20.00' sales-tax-or-vat amount=120 priceIncludesTax=yes --country US -q
expect "accepts a currency symbol in a value" '$2,078.11' mortgage-payment 'price=$450,000' rate=5.5% --country US -q
expect "shows the inputs of a calculator" 'tipRate  Tip on pre-tax bill' show tip-and-bill-split --country US
expect "finds calculators" 'tip-and-bill-split' search split bill
expect "lists a category" 'gross-to-net-pay-estimate' list taxes
expect "suggests a calculator for a typo" 'Did you mean: mortgage-payment' mortage-payment
expect "names the inputs for an unknown one" 'Its inputs are: price, down, rate, years' mortgage-payment cost=1
expect "rejects an unknown country" 'There'"'"'s no country "XX"' mortgage-payment --country XX
expect "prints the version" 'calculum ' --version

exit $FAILED
