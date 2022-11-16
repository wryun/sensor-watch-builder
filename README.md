Build firmware for the [Sensor Watch](https://sensorwatch.net) online.

Proof of concept. Attempts to work with and without JS, mostly.

Run locally like (and connect to localhost:8080):

    docker build . -t swb && docker run --name swb -p 8080:8080 --rm swb

[Sensor Watch Builder](https://sensor-watch-builder.fly.dev/)
