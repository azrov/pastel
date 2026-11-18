# Pastel.Testing

Unit testing.

  Write a class with published methods; each method is one test:

    type
      TGreetingTests = class(TTestSuite)
      published
        procedure GreetsByName;
      end;

    procedure TGreetingTests.GreetsByName;
    begin
      AssertEquals('Hello, Ali!', MakeGreeting('Ali'));
    end;

    initialization
      RegisterTests(TGreetingTests);

  "pastel test" finds the units in tests/, builds them into one program
  and runs it. A failing assert shows the file and line of the test.

`uses Pastel.Testing;` · source: [framework/src/pastel.testing.pas](../../framework/src/pastel.testing.pas)

**Contents:** [ETestFailure](#etestfailure) · [ETestSkipped](#etestskipped) · [TTestSuite](#ttestsuite) · [RegisterTests](#registertests) · [Test](#test) · [AssertTrue](#asserttrue) · [AssertFalse](#assertfalse) · [AssertEquals](#assertequals) · [AssertEquals](#assertequals) · [AssertEquals](#assertequals) · [AssertEquals](#assertequals) · [AssertNotEquals](#assertnotequals) · [AssertNotEquals](#assertnotequals) · [AssertContains](#assertcontains) · [AssertStartsWith](#assertstartswith) · [AssertNil](#assertnil) · [AssertNotNil](#assertnotnil) · [AssertRaises](#assertraises) · [AssertRaises](#assertraises) · [Fail](#fail) · [Skip](#skip) · [RunTests](#runtests) · [HumanName](#humanname)

## Types

### ETestFailure

```pascal
type ETestFailure = class(Exception)
```

Raised by a failing assert.

### ETestSkipped

```pascal
type ETestSkipped = class(Exception)
```

Raised by Skip.

### TTestSuite

```pascal
type TTestSuite = class
```

published methods (the tests) need RTTI

| | |
|---|---|
| `procedure SetUp` | Runs before / after every test of the suite. |
| `procedure TearDown` |  |

## Other types

| | |
|---|---|
| `type TTestSuiteClass = class of TTestSuite` |  |
| `type TTestProc = procedure` |  |
| `type TTestMethod = procedure` |  |

## Routines

### RegisterTests

```pascal
procedure RegisterTests(ASuite: TTestSuiteClass)
```

### Test

```pascal
procedure Test(const AName: string; AProc: TTestProc)
```

A single test as a plain procedure (no class needed).

### AssertTrue

```pascal
procedure AssertTrue(Condition: Boolean; const Msg: string = '')
```

### AssertFalse

```pascal
procedure AssertFalse(Condition: Boolean; const Msg: string = '')
```

### AssertEquals

```pascal
procedure AssertEquals(const Expected: string; const Actual: string; const Msg: string = '')
```

### AssertEquals

```pascal
procedure AssertEquals(Expected: Int64; Actual: Int64; const Msg: string = '')
```

### AssertEquals

```pascal
procedure AssertEquals(Expected: Double; Actual: Double; Delta: Double = 1E-9; const Msg: string = '')
```

### AssertEquals

```pascal
procedure AssertEquals(Expected: Boolean; Actual: Boolean; const Msg: string = '')
```

### AssertNotEquals

```pascal
procedure AssertNotEquals(const NotExpected: string; const Actual: string; const Msg: string = '')
```

### AssertNotEquals

```pascal
procedure AssertNotEquals(NotExpected: Int64; Actual: Int64; const Msg: string = '')
```

### AssertContains

```pascal
procedure AssertContains(const Part: string; const Actual: string; const Msg: string = '')
```

### AssertStartsWith

```pascal
procedure AssertStartsWith(const Prefix: string; const Actual: string; const Msg: string = '')
```

### AssertNil

```pascal
procedure AssertNil(P: Pointer; const Msg: string = '')
```

### AssertNotNil

```pascal
procedure AssertNotNil(P: Pointer; const Msg: string = '')
```

### AssertRaises

```pascal
procedure AssertRaises(AClass: ExceptClass; AProc: TTestProc; const Msg: string = '')
```

### AssertRaises

```pascal
procedure AssertRaises(AClass: ExceptClass; AMethod: TTestMethod; const Msg: string = '')
```

### Fail

```pascal
procedure Fail(const Msg: string)
```

### Skip

```pascal
procedure Skip(const Reason: string)
```

### RunTests

```pascal
function RunTests: Integer
```

Runs the registered tests. Command line: [--json] [filter...].
Returns the exit code: 0 if everything passed.

### HumanName

```pascal
function HumanName(const Identifier: string): string
```

"GreetsByName" -> "greets by name"

