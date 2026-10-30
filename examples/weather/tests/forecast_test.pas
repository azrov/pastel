{ Tests for src/services/forecast.pas with answers saved from the service,
  so they run without a network. Run them with: pastel test }
unit Forecast_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Forecast;

type
  TForecastTests = class(TTestSuite)
  private
    procedure ParseNothing;
    procedure ParseServiceError;
  published
    procedure BuildsTheAddresses;
    procedure ReadsAPlace;
    procedure UnknownPlaceIsExplained;
    procedure ReadsTheDays;
    procedure ServiceErrorsAreExplained;
    procedure DescribesTheWeather;
  end;

implementation

const
  PlaceAnswer =
    '{"results":[{"id":587084,"name":"Baku","latitude":40.37767,"longitude":49.89201,' +
    '"elevation":-28.0,"feature_code":"PPLC","country_code":"AZ","timezone":"Asia/Baku",' +
    '"population":1116513,"country_id":587116,"country":"Azerbaijan","admin1":"Baku"}],' +
    '"generationtime_ms":0.5}';
  NoPlaceAnswer = '{"generationtime_ms":0.3}';
  ForecastAnswer =
    '{"latitude":40.375,"longitude":49.875,"timezone":"Asia/Baku","daily_units":' +
    '{"time":"iso8601","weather_code":"wmo code","temperature_2m_min":"°C",' +
    '"temperature_2m_max":"°C","precipitation_sum":"mm"},"daily":{"time":' +
    '["2026-10-30","2026-10-31"],"weather_code":[3,61],"temperature_2m_min":[12.1,11.4],' +
    '"temperature_2m_max":[18.6,16.0],"precipitation_sum":[0.0,2.3]}}';
  ErrorAnswer = '{"error":true,"reason":"Invalid value for parameter forecast_days"}';

procedure TForecastTests.BuildsTheAddresses;
var
  P: TPlace;
begin
  AssertEquals('https://geocoding-api.open-meteo.com/v1/search?name=New%20York&count=1&language=tr&format=json',
    PlaceUrl('New York', 'tr'));
  P := Default(TPlace);
  P.Latitude := 40.37767;
  P.Longitude := 49.89201;
  AssertContains('latitude=40.3777&longitude=49.892&', ForecastUrl(P, 3, False));
  AssertContains('forecast_days=3', ForecastUrl(P, 3, False));
  AssertContains('temperature_unit=fahrenheit', ForecastUrl(P, 3, True));
end;

procedure TForecastTests.ReadsAPlace;
var
  P: TPlace;
begin
  P := ParsePlace(PlaceAnswer, 'baku');
  AssertEquals('Baku', P.Name);
  AssertEquals('Azerbaijan', P.Country);
  AssertEquals(40.37767, P.Latitude, 1e-6);
  AssertEquals('Baku, Azerbaijan', PlaceTitle(P));
end;

procedure TForecastTests.ParseNothing;
begin
  ParsePlace(NoPlaceAnswer, 'Atlantis');
end;

procedure TForecastTests.UnknownPlaceIsExplained;
begin
  try
    ParseNothing;
    Fail('no exception');
  except
    on E: EWeatherError do
      AssertEquals('no place called "Atlantis" was found', E.Message);
  end;
end;

procedure TForecastTests.ReadsTheDays;
var
  F: TForecast;
begin
  F := ParseForecast(ForecastAnswer);
  AssertEquals(2, Length(F.Days));
  AssertEquals('°C', F.TempUnit);
  AssertEquals('2026-10-31', FormatDateTime('yyyy-mm-dd', F.Days[1].Date));
  AssertEquals(61, F.Days[1].Code);
  AssertEquals(11.4, F.Days[1].TempMin, 1e-9);
  AssertEquals(2.3, F.Days[1].Rain, 1e-9);
end;

procedure TForecastTests.ParseServiceError;
begin
  ParseForecast(ErrorAnswer);
end;

procedure TForecastTests.ServiceErrorsAreExplained;
begin
  AssertRaises(EWeatherError, @ParseServiceError);
end;

procedure TForecastTests.DescribesTheWeather;
begin
  AssertEquals('clear sky', WeatherText(0));
  AssertEquals('light rain', WeatherText(61));
  AssertEquals('thunderstorm with hail', WeatherText(99));
  AssertEquals('unknown', WeatherText(42));
end;

initialization
  RegisterTests(TForecastTests);
end.
