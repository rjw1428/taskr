# Mutation testing

`run.sh` mutates one source file at a time (flipped operators, negated
conditions, deleted statements) and reruns only that file's tests. A mutant
that survives means the tests would not notice that change.

```
dart pub global activate mutation_test   # once
tool/mutation/run.sh                     # all targets, ~12 min
tool/mutation/run.sh goal_planning       # one target
```

Targets live in `targets/<name>.xml`. To add one, copy an existing file and
point it at a source file plus the test files that cover it. Keep targets to
pure-logic files: Firestore-backed services run ~20 s per mutant.

Reports are written to `report/` (gitignored). The run exits non-zero when any
target has survivors. Not every survivor is a gap: a mutation the app can never
trigger (e.g. an index past the end of a list the widget never produces) is an
equivalent mutant and can be left alone.
