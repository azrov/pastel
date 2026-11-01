# components

A **library of components** that other Pastel projects use: a control and a non-visual component, each a small example of a way to write one.

| Component | What it shows |
|---|---|
| `TStarRating` (`src/controls/starrating.pas`) | A control that draws itself: `Measure`, `Paint`, mouse and keys |
| `TFormMemory` (`src/controls/formmemory.pas`) | A non-visual component, made from `TDataBinding`, that writes a file |

Use it from an app (see [`examples/components-demo`](../components-demo)):

```toml
[dependencies]
components = { path = "../components" }
```

Its controls then appear in the designer's toolbox of that app, and work in its `.pform` files like the built-in ones. `TCurrencyEdit` and `TDatePicker` started here too; since 1.0.0-rc.4 they are in the framework (`Pastel.Inputs`), and their source is the example for a control made from another one and a control with a popup. How to write components: [docs/components.md](../../docs/components.md).

```sh
pastel build     # checks that every unit compiles
pastel test      # tests/starrating_test.pas
```
