{ Talking to Open-Meteo (https://open-meteo.com): the addresses to ask and
  reading the answers. No network code here, so it is easy to test. }
unit Forecast;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  EWeatherError = class(Exception);

  TPlace = record
    Name, Region, Country, Timezone: string;
    Latitude, Longitude: Double;
  end;

  TDay = record
    Date: TDateTime;
    Code: Integer;           { WMO weather code }
    TempMin, TempMax, Rain: Double;
  end;

  TForecast = record
    Days: array of TDay;
    TempUnit, RainUnit: string;
  end;

function PlaceUrl(const Name, Language: string): string;
function ForecastUrl(const Place: TPlace; Days: Integer; Imperial: Boolean): string;

{ The first place found; EWeatherError when there is none. }
function ParsePlace(const Json, Name: string): TPlace;
function ParseForecast(const Json: string): TForecast;

{ 'Baku, Azerbaijan' }
function PlaceTitle(const P: TPlace): string;
{ WMO code -> words: 61 -> 'light rain' }
function WeatherText(Code: Integer): string;

implementation

uses
  fpjson, Pastel.Json, Pastel.Http;

function Num(V: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FormatFloat('0.####', V, FS);
end;

function PlaceUrl(const Name, Language: string): string;
begin
  Result := 'https://geocoding-api.open-meteo.com/v1/search?' +
    QueryString(['name', Name, 'count', '1', 'language', Language, 'format', 'json']);
end;

function ForecastUrl(const Place: TPlace; Days: Integer; Imperial: Boolean): string;
begin
  Result := 'https://api.open-meteo.com/v1/forecast?' + QueryString([
    'latitude', Num(Place.Latitude),
    'longitude', Num(Place.Longitude),
    'daily', 'weather_code,temperature_2m_min,temperature_2m_max,precipitation_sum',
    'timezone', 'auto',
    'forecast_days', IntToStr(Days)]);
  if Imperial then
    Result := Result + '&' + QueryString(['temperature_unit', 'fahrenheit', 'precipitation_unit', 'inch']);
end;

function ParsePlace(const Json, Name: string): TPlace;
var
  Doc: TJSONData;
begin
  Doc := ParseJson(Json);
  try
    if not JHas(Doc, 'results[0].latitude') then
      raise EWeatherError.CreateFmt('no place called "%s" was found', [Name]);
    Result.Name := JStr(Doc, 'results[0].name');
    Result.Region := JStr(Doc, 'results[0].admin1');
    Result.Country := JStr(Doc, 'results[0].country');
    Result.Timezone := JStr(Doc, 'results[0].timezone');
    Result.Latitude := JFloat(Doc, 'results[0].latitude');
    Result.Longitude := JFloat(Doc, 'results[0].longitude');
  finally
    Doc.Free;
  end;
end;

function ParseForecast(const Json: string): TForecast;
var
  Doc: TJSONData;
  Dates: TJsonItems;
  I: Integer;
  Path: string;
begin
  Doc := ParseJson(Json);
  try
    if JHas(Doc, 'error') and (JStr(Doc, 'reason') <> '') then
      raise EWeatherError.Create('the weather service says: ' + JStr(Doc, 'reason'));
    Result.TempUnit := JStr(Doc, 'daily_units.temperature_2m_max', '°C');
    Result.RainUnit := JStr(Doc, 'daily_units.precipitation_sum', 'mm');
    Dates := JArray(Doc, 'daily.time');
    SetLength(Result.Days, Length(Dates));
    for I := 0 to High(Dates) do
    begin
      Path := Format('[%d]', [I]);
      with Result.Days[I] do
      begin
        Date := EncodeDate(StrToInt(Copy(Dates[I].AsString, 1, 4)),
          StrToInt(Copy(Dates[I].AsString, 6, 2)), StrToInt(Copy(Dates[I].AsString, 9, 2)));
        Code := JInt(Doc, 'daily.weather_code' + Path, -1);
        TempMin := JFloat(Doc, 'daily.temperature_2m_min' + Path);
        TempMax := JFloat(Doc, 'daily.temperature_2m_max' + Path);
        Rain := JFloat(Doc, 'daily.precipitation_sum' + Path);
      end;
    end;
  finally
    Doc.Free;
  end;
end;

function PlaceTitle(const P: TPlace): string;
begin
  Result := P.Name;
  if (P.Region <> '') and (P.Region <> P.Name) then
    Result := Result + ', ' + P.Region;
  if P.Country <> '' then
    Result := Result + ', ' + P.Country;
end;

function WeatherText(Code: Integer): string;
begin
  case Code of
    0: Result := 'clear sky';
    1: Result := 'mainly clear';
    2: Result := 'partly cloudy';
    3: Result := 'overcast';
    45, 48: Result := 'fog';
    51, 53, 55: Result := 'drizzle';
    56, 57: Result := 'freezing drizzle';
    61: Result := 'light rain';
    63: Result := 'rain';
    65: Result := 'heavy rain';
    66, 67: Result := 'freezing rain';
    71: Result := 'light snow';
    73: Result := 'snow';
    75: Result := 'heavy snow';
    77: Result := 'snow grains';
    80, 81: Result := 'rain showers';
    82: Result := 'violent rain showers';
    85, 86: Result := 'snow showers';
    95: Result := 'thunderstorm';
    96, 99: Result := 'thunderstorm with hail';
  else
    Result := 'unknown';
  end;
end;

end.
