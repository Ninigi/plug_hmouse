# PlugHMouse

An HMAC authentication plug.
Replace `Plug.Parsers` with `PlugHMouse` and you are ready to go.

For more information about the awesomeness of Plug refer to https://github.com/elixir-lang/plug

## Simple Example

Lets say you are running a Phoenix app to receive Shopify webhooks and want to
verify the authenticity, open up your `endpoint.ex` and replace `Plug.Parsers`
like this:

```elixir
defmodule MyApp.Endpoint do
  # ...

  # plug Plug.Parsers,
  #   parsers: [:urlencoded, :multipart, :json],
  #   pass: ["*/*"],
  #   json_decoder: Poison

  plug PlugHMouse,
    validate: {"x-shopify-hmac-sha256", "MySecretKey123"}

  # ...
end
```

Add the dependency in your mix.exs:

```elixir
defmodule MyApp.Mixfile do
  use Mix.Project

  # ...

  defp deps do
    [{:phoenix, "~> 1.2.1"},
     {:phoenix_pubsub, "~> 1.0"},
     {:phoenix_ecto, "~> 3.0"},
     {:postgrex, ">= 0.0.0"},
     {:phoenix_html, "~> 2.6"},
     {:phoenix_live_reload, "~> 1.0"},
     {:gettext, "~> 0.11"},
     {:cowboy, "~> 1.0"},
     {:plug_hmouse, "~> 0.0.1"}]
  end

  # ...
end
```

Run `mix deps.get`, now all incomming requests will get rejected if they are missing the HMAC header or are not signed correctly!

## Installation

The package can be installed by adding `plug_hmouse` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:plug_hmouse, "~> 0.0.1"}]
end
```

HMouse will consume the response body, like Plug.Parsers does, so make sure you do not have any plugs depending
on the body, or write a custom parser to process the body.

## Options

There are a few options you can pass to the plug to get some more control:

```elixir
plug PlugHMouse,
  validate: {"hmac-md5", "MySecretKey123"}
  only: ["webhooks/verified"],
  error_views: [
    {"json", MyApp.JSONErrorStrategy, "403.json", MyApp.JSONResponseStrategy},
    {"urlencoded", MyApp.URLENCODEDErrorStrategy, "403", PlugHMouse.URLENCODEDResponse}
  ],
  plug_parsers: [
    parsers: [:urlencoded, :multipart, MyApp.MyJSONParser],
    pass: ["application/*"],
    json_decoder: Poison
  ],
  hash_algo: :md5,
  digest: fn string -> Base.encode16(string) end,
  split_digest: true
```

### validate (mandatory)

Usually a Tuple in the form of `{"hmac-header-name", "my-secret-key"}`, can also be a List of Tuples
of the same form.

* **header-name** This is the string used to sign the request body, in the Shopify example, you can find it under your webhhooks

* **secret-key** Tell HMouse where to find the signature! In the Shopify example it is `X-Shopify-Hmac-SHA256`, but since
  all Conn headers are lowercase, we need to pass `"x-shopify-hmac-sha256"`

### error_views (optional)

If you do not want the default "HMAC Error" message in your response, or want to handle the response yourself
(for example for logging), you can define custom strategies. Pass a list of Tuples to `:error_views` in the form of:
`{"content-type", MyApp.RenderStrategy, "template_name", MyApp.ResponseStrategy}` and define your strategies:

```elixir
defmodule MyApp.RenderStrategy do
  @behaviour PlugHMouse.RenderStrategy

  # template_name is used for pattern matching purposes
  def hmouse_render(template_name) do
    "Error: Learn to sign a message, dummy!"
  end
end

defmodule MyApp.ResponseStrategy do
  @behaviour PlugHMouse.ResponseStrategy

  # response_body is the return value of MyApp.RenderStrategy.hmouse_render(template_name)
  # Note that it is your responsibility to make the response, otherwise Plug will raise an error.
  def respond(conn, response_body) do
    conn
    |> put_resp_content_type("application/content-type")
    |> resp(401, response_body)
    |> send_resp()
  end
end
```

### hash_algo (optional, default: :sha256)

If you want to use a different hashing algorythm, you can pass one of these values to `:hash_algo`:

* :md5
* :sha
* :sha224
* :sha256
* :sha384
* :sha512

HMouse uses [erlangs crypto under the hood](http://erlang.org/doc/man/crypto.html), so all values allowed
for `:crypto.hmac` are usable.

### digest (optional, default: Base.encode64/2)

You can define your own encoding function.

### split_digest (optional, default: `false`)

Determines whether the digest of the request is in the format:

```
header_name: algo=digest
eg. X-Hub-Signature: sha1=7d38cdd689735b008b3c702edd92eea23791c5f6
```

Or:

```
header_name: digest
eg. X-Shopify-Hmac-SHA256: fTjN1olzWwCLPHAu3ZLuojeRxfY=
```

If `split_digest` is set to `true` then the first form will be assumed and the value will be split at the equals sign, with the latter part being taken as the digest. If it is `false` then the second form will be assumed and the full value will be considered the digest.

**Note**: Currently this feature does not use the first half of the value as the hash algorithm, you still have to define the algorithm manually with `hash_algo`.

### plug_parsers (optional, all values for Plug.Parsers options are allowed)

Due to a restriction to Plug.Conn.read_body, HMouse effectively rewrites Plug.Parsers.JSON and
Plug.Parsers.URLENCODED to be able to encode the request body before it is consumed by the parsers,
but uses regular Plug.Parsers to pipe through to avoid functional duplication as much as possible.

This means, you can simply pass all the options you would normally pass to Plug.Parses here:

```elixir
plug PlugHMouse,
  validate: {"hmac-header", "MySecretKey123"},
  plug_parsers: [
    parsers: [:urlencoded, :multipart, :json],
    pass: ["application/vnd.api+json"],
    json_decoder: Poison
  ]
```

## Custom Parsers

HMouse tries to keep the original functionality of Plug.Parsers, meaning it enables you to write custom parsers as well.
Additional to Plug.Parsers behaviour implementation, you need to set the private hmouse hash assign in conn. To keep it simple,
HMouse provides the `PlugHMouse.put_plug_hmouse_hash(conn, body, opts)` function. It returns the new conn, so you can use it to pipe through:

```elixir
defmodule MyApp.MyParser do
  @behaviour Plug.Parsers

  # ...

  # Do something to satisfy your parsing needs and add the hmouse hash.
  # This is taken from Plug.Parsers.URLENCODED and modified to add the hash:
  def parse(conn, "application", "x-www-form-urlencoded", _headers, opts) do
    case Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        Plug.Conn.Utils.validate_utf8!(body, Plug.Parsers.BadEncodingError, "urlencoded body")
        {:ok, Plug.Conn.Query.decode(body), PlugHMouse.put_plug_hmouse_hash(conn, body, opts)}
      {:more, _data, conn} ->
        {:error, :too_large, conn}
      {:error, :timeout} ->
        raise Plug.TimeoutError
      {:error, _} ->
        raise Plug.BadRequestError
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end
```

## Multiple Headers

If you need to validate different headers - for example if you have a single app handling multiple webhooks - you can pass a list
to the `:validate` option:

```elixir
plug PlugHMouse,
  validate: [
    {"hmac-header", "MySecretKey123"},
    {"other-hmac-header", "MyOtherSecretKey123"}
  ]
```

If you need different hashing strategies, you can set them like this:

```elixir
plug PlugHMouse,
  validate: [
    {"hmac-header", "MySecretKey123", :sha256, &Base.encode16/1},
    {"other-hmac-header", "MyOtherSecretKey123", :sha256, &Base.encode64/1}
  ]
```
