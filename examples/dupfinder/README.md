# dupfinder

Finds files with the same content. An example of a Pastel console tool; see
`docs/guide-cli.md` for how it was built.

```
pastel run -- ~/Pictures ~/Downloads
pastel run -- -p "*.jpg" --min-size 100k ~/Pictures
pastel run -- --json ~/Documents > duplicates.json
pastel test
pastel package --target windows
```

It compares sizes first, and reads only files that have the same size as
another file. Nothing is deleted: it only reports.
