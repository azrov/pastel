# weather

The weather for the next days, from [Open-Meteo](https://open-meteo.com) (free, no
account needed). An example of a Pastel console tool that calls a web API; see
`docs/guide-cli.md`.

```
$ weather Baku
Baku, Azerbaijan
Day         Weather         Min   Max    Rain
----------  -------------  ----  ----  ------
Fri 30 Oct  overcast       12°C  19°C  0.0 mm
Sat 31 Oct  light rain     11°C  16°C  2.3 mm
Sun 1 Nov   partly cloudy  10°C  17°C  0.0 mm
```

```
pastel run -- Baku
pastel run -- --days 7 --units imperial "New York"
pastel run -- --json Ankara
pastel test            # works without a network: the answers are saved in the test
```

The default place, units and language can be set once in
`~/.config/weather/config.toml` (see `config.example.toml`) or with the
environment variables `WEATHER_CITY`, `WEATHER_UNITS`, `WEATHER_LANGUAGE`.
