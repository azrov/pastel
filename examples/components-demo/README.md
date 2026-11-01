# components-demo

An order form that uses the components of [`examples/components`](../components), a library project:

```toml
[dependencies]
components = { path = "../components" }
```

- `TCurrencyEdit` for the price (`PriceEdit.Value` is a `Currency`),
- `TDatePicker` for the delivery date,
- `TStarRating` for the customer's priority,
- `TFormMemory` remembers the customer and the price for the next start.

Open `src/forms/Home.pform` in VS Code: the library's controls are at the front of the designer's toolbox.

```sh
pastel run
PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/linux/debug/components-demo   # the UI test
```
