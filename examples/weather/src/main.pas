{ weather - the weather for the next days, from Open-Meteo.
  An example of a Pastel console tool that calls a web API: HTTPS, JSON,
  settings from a file or the environment, a table. Try: pastel run -- Baku }
program weather;

{$mode objfpc}{$H+}

uses
  SysUtils, fpjson, Pastel.Args, Pastel.Config, Pastel.Http, Pastel.Json, Pastel.Term,
  AppInfo, Forecast;

{ GET, with the service's own explanation when it says no }
function Fetch(const Url: string): string;
var
  R: THttpResponse;
begin
  R := HttpGet(Url);
  if not R.Ok and (Pos('"reason"', R.Body) > 0) then
    raise EWeatherError.Create('the weather service says: ' + JStr(ParseJson(R.Body), 'reason'));
  R.RaiseForStatus;
  Result := R.Body;
end;

procedure PrintTable(const Place: TPlace; const F: TForecast);
var
  T: TTable;
  D: TDay;
begin
  WriteLn(Bold(PlaceTitle(Place)));
  T := TTable.Create(['Day', 'Weather', 'Min', 'Max', 'Rain']);
  try
    T.SetAlign(2, alRight);
    T.SetAlign(3, alRight);
    T.SetAlign(4, alRight);
    for D in F.Days do
      T.AddRow([FormatDateTime('ddd d mmm', D.Date), WeatherText(D.Code),
        Format('%.0f%s', [D.TempMin, F.TempUnit]),
        Format('%.0f%s', [D.TempMax, F.TempUnit]),
        Format('%.1f %s', [D.Rain, F.RainUnit])]);
    T.Print;
  finally
    T.Free;
  end;
end;

procedure PrintJson(const Place: TPlace; const F: TForecast);
var
  Days: TJSONArray;
  D: TDay;
  Doc: TJSONObject;
begin
  Days := TJSONArray.Create;
  for D in F.Days do
    Days.Add(JObject(['date', FormatDateTime('yyyy-mm-dd', D.Date), 'weather', WeatherText(D.Code),
      'min', D.TempMin, 'max', D.TempMax, 'rain', D.Rain]));
  Doc := JObject(['place', PlaceTitle(Place), 'temperature_unit', F.TempUnit,
    'rain_unit', F.RainUnit, 'days', Days]);
  try
    WriteLn(ToJson(Doc, True));
  finally
    Doc.Free;
  end;
end;

var
  Args: TArgs;
  Config: TConfig;
  City: string;
  Place: TPlace;
  F: TForecast;
begin
  Config := TConfig.Create('weather');
  Args := TArgs.Create(AppName, 'The weather for the next days (data: open-meteo.com).');
  try
    Config.SetDefault('units', 'metric');
    Config.SetDefault('language', 'en');
    Config.LoadStandard;

    Args.Version := AppVersion;
    Args.Positional('city', 'Place to show; default: "city" in the settings').Optional;
    Args.Option('days', 'd', 'How many days', '3').IntRange(1, 16);
    Args.Option('units', 'u', 'metric (°C, mm) or imperial (°F, inch)', Config.Get('units'))
      .Choices(['metric', 'imperial']);
    Args.Flag('json', '', 'Print JSON');
    Args.Example('weather Baku');
    Args.Example('weather --days 7 --units imperial "New York"');
    Args.Parse;

    City := Args.Get('city');
    if City = '' then
      City := Config.Get('city');
    if City = '' then
    begin
      Error('which place? Give one: weather Baku');
      Info('or set it once: city = "Baku" in ~/.config/weather/config.toml, or WEATHER_CITY=Baku');
      Halt(2);
    end;

    try
      Place := ParsePlace(Fetch(PlaceUrl(City, Config.Get('language'))), City);
      F := ParseForecast(Fetch(ForecastUrl(Place, Args.GetInt('days'), Args.Get('units') = 'imperial')));
    except
      on E: EWeatherError do
      begin
        Error(E.Message);
        Halt(1);
      end;
      on E: EHttpError do
      begin
        Error(E.Message);
        Halt(1);
      end;
    end;

    if Args.Has('json') then
      PrintJson(Place, F)
    else
      PrintTable(Place, F);
  finally
    Args.Free;
    Config.Free;
  end;
end.
