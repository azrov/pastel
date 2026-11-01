# components

A **library of components** that other Pastel projects use: three controls and one non-visual component, each a small example of a way to write one.

| Component | What it shows |
|---|---|
| `TStarRating` (`src/controls/starrating.pas`) | A control that draws itself: `Measure`, `Paint`, mouse and keys |
| `TCurrencyEdit` (`src/controls/currencyedit.pas`) | A control made from an existing one (`TEdit`) with a new property (`Value`) |
| `TDatePicker` (`src/controls/datepicker.pas`) | A control with a popup (`TPopup` with a `TCalendarView`) |
| `TFormMemory` (`src/controls/formmemory.pas`) | A non-visual component, made from `TDataBinding`, that writes a file |

Use it from an app (see [`examples/components-demo`](../components-demo)):

```toml
[dependencies]
components = { path = "../components" }
```

Its controls then appear in the designer's toolbox of that app, and work in its `.pform` files like the built-in ones. How to write components: [docs/components.md](../../docs/components.md).

```sh
pastel build     # checks that every unit compiles
pastel test      # tests/money_test.pas
```
