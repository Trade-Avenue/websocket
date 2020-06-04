defmodule Websocket.Conn do
  use TypedStruct

  @type gen_tcp_options :: []

  @type ssl_options :: []

  @type websocket_options :: %{
          compress: boolean,
          protocols: [{binary, module}]
        }

  @type http_options :: %{
          keepalive: timeout,
          transform_header_name: (binary -> binary),
          version: binary
        }

  @type http2_options :: %{keepalive: timeout}

  @type connect_options :: %{
          connect_timeout: timeout,
          protocols: [:http | :http2],
          retry: non_neg_integer,
          retry_timeout: pos_integer,
          trace: boolean,
          transport: :tcp | :tls,
          transport_opts: [gen_tcp_options] | [ssl_options],
          ws_opts: websocket_options,
          http_opts: http_options,
          http2_opts: http2_options
        }

  typedstruct do
    field :host, String.t(), enforce: true
    field :port, integer, enforce: true
    field :path, String.t(), enforce: true

    field :headers, [{binary, iodata}]

    field :connect_opts, connect_options, default: %{}

    field :pid, pid
    field :monitor, reference

    field :stream, reference

    field :state, term, default: %{}
  end

  def new!(args), do: struct!(__MODULE__, args)

  @spec add_pid(t, pid) :: t
  def add_pid(conn, pid),
    do: %{conn | pid: pid, monitor: Process.monitor(pid)}

  @spec update_state(t, term) :: t
  def update_state(conn, state), do: %{conn | state: state}

  @spec add_stream(t, reference) :: t
  def add_stream(conn, stream), do: %{conn | stream: stream}
end
