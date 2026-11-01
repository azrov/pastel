#!/bin/sh
# Every feature people use is documented with an example:
#   every control and component in docs/controls.md (### TName),
#   every command in docs/commands.md (## pastel name),
#   every example in docs/README.md, with a README of its own.
# Run by tests/run.sh; prints what is missing and fails.
cd "$(dirname "$0")/.."
PASTEL="${PASTEL:-$PWD/bin/pastel}"
missing=0
for c in $("$PASTEL" schema | grep -o '"name":"T[A-Za-z0-9]*","container":[a-z]*,"form":false,"nonvisual":[a-z]*,"project":false' | sed 's/"name":"\([^"]*\)".*/\1/'); do
  grep -q "^### $c\$" docs/controls.md || { echo "docs/controls.md: no section \"### $c\" (with a .pform and a code example)"; missing=$((missing + 1)); }
done
for cmd in $("$PASTEL" help | sed -n '/^Commands:/,/^$/p' | awk 'NR > 1 && NF { print $1 }' | sort -u); do
  grep -q "^## pastel $cmd\$" docs/commands.md || { echo "docs/commands.md: no section \"## pastel $cmd\""; missing=$((missing + 1)); }
done
for ex in examples/*/; do
  ex="${ex%/}"; name="${ex#examples/}"
  [ -f "$ex/README.md" ] || { echo "$ex: no README.md"; missing=$((missing + 1)); }
  grep -q "examples/$name/README.md" docs/README.md || { echo "docs/README.md: example \"$name\" is not listed"; missing=$((missing + 1)); }
done
if [ "$missing" -gt 0 ]; then
  echo "$missing thing(s) without documentation (see CONTRIBUTING.md: every feature comes with its docs)"
  exit 1
fi
echo "docs: every control, command and example is documented"
