# Testing

Tests live in the `tests/` folder of a project. Run them with:

```sh
pastel test                # all tests
pastel test greeting       # only tests whose suite or name contains "greeting"
pastel test --json         # results as JSON, for editors and CI tools
```

`pastel test` builds every unit in `tests/` into one test program, together with your project's own units, and runs it. The exit code is 1 when a test fails, so it works in CI as is. In VS Code: *Pastel: Run Tests*, or *Run Tests* in the Pastel panel.

## Writing tests

A test file is a unit. Each published method of a `TTestSuite` class is one test:

```pascal
unit Greeting_Test;

{$mode objfpc}{$H+}

interface

uses
  Pastel.Testing, Greeting;

type
  TGreetingTests = class(TTestSuite)
  published
    procedure GreetsByName;
    procedure EmptyNameGreetsTheWorld;
  end;

implementation

procedure TGreetingTests.GreetsByName;
begin
  AssertEquals('Hello, Ali!', MakeGreeting('Ali'));
end;

procedure TGreetingTests.EmptyNameGreetsTheWorld;
begin
  AssertStartsWith('Hello, world', MakeGreeting(''));
end;

initialization
  RegisterTests(TGreetingTests);
end.
```

Method names become readable test names: `GreetsByName` is shown as "greets by name", and the suite `TGreetingTests` as "Greeting".

```
Greeting
  PASS greets by name (0 ms)
  FAIL empty name greets the world
       expected "Hello, !" to start with "Hello, world"
       at tests/greeting_test.pas:24

Tests: 1 failed, 1 passed, 2 total (1 ms)
```

A failing assert shows the file and line of the test. An unexpected exception is reported as an error with its class, message and line.

### Set up and tear down

Override `SetUp` and `TearDown` to prepare and clean up for every test. Each test gets a fresh suite object, so fields start empty in every test.

```pascal
type
  TStoreTests = class(TTestSuite)
  private
    FStore: TStore;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AddsItems;
  end;

procedure TStoreTests.SetUp;
begin
  FStore := TStore.Create;
end;

procedure TStoreTests.TearDown;
begin
  FStore.Free;
end;
```

### Tests without a class

For a quick check, a plain procedure works too:

```pascal
procedure AddsNumbers;
begin
  AssertEquals(4, 2 + 2);
end;

initialization
  Test('adds numbers', @AddsNumbers);
```

## Asserts

| Assert | Passes when |
|---|---|
| `AssertTrue(Cond)` / `AssertFalse(Cond)` | the condition is true / false |
| `AssertEquals(Expected, Actual)` | equal; for text, whole numbers, booleans and floating point numbers (with an optional `Delta`) |
| `AssertNotEquals(NotExpected, Actual)` | different (text, whole numbers) |
| `AssertContains(Part, Actual)` | `Actual` contains `Part` |
| `AssertStartsWith(Prefix, Actual)` | `Actual` starts with `Prefix` |
| `AssertNil(P)` / `AssertNotNil(P)` | the pointer or object is / is not nil |
| `AssertRaises(EClass, @Proc)` | calling `Proc` raises `EClass` (or a descendant); `Proc` can be a method of the suite |
| `Fail(Msg)` | never: fails with a message |
| `Skip(Reason)` | never: marks the test as skipped |

Every assert takes an optional last argument with your own message, shown next to the failure.

## Good to know

- Tests are compiled in debug mode with range and overflow checks, so mistakes like reading past the end of an array show up as errors.
- The define `PASTEL_TEST` is set while compiling tests: `{$IFDEF PASTEL_TEST} ... {$ENDIF}`.
- The test program is built in `build/<platform>/test/`; you never need to touch it.
