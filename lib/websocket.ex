defmodule Websocket do
  alias Websocket.Conn

  @type state :: term

  @type frame ::
          :ping
          | :pong
          | :close
          | {:ping | :pong | :text | :binary | :close, binary}
          | {:close, non_neg_integer, binary}

  @doc "Creates a new state for the websocket connection."
  @callback new_state(Conn.t(), protocols :: [binary], headers :: [{binary, binary}]) :: state

  @doc """
  Processes messages sent from the client application to the
  websocket server and optionally tracks state for the connection.
  """
  @callback handle_push(message :: term, state) :: {:push | :close, frame, state} | {:ok, state}

  @doc """
  Processes messages received by the client application from the
  remote websocket server.
  """
  @callback handle_receive(frame, state) :: {:push | :close, frame, state} | {:ok, state}

  @spec start_link(module, any, GenServer.options()) :: GenServer.on_start()
  defdelegate start_link(module, args, options \\ []), to: GenServer

  defmacro __using__(args) do
    debug = Keyword.get(args, :debug, false)

    quote bind_quoted: [debug: debug], location: :keep, generated: true do
      alias Websocket.Conn

      use GenServer

      require Logger

      @behaviour Websocket

      @impl GenServer
      def init(args) do
        Process.flag(:trap_exit, true)

        {:ok, Conn.new!(args), {:continue, :connect}}
      end

      @impl GenServer
      def handle_continue(:connect, conn) do
        %{host: host, port: port, connect_opts: opts} = conn

        log_debug("Connecting to #{host}:#{port}.")

        {:ok, pid} = :gun.open(host, port, opts)

        {:ok, :http} = :gun.await_up(pid)

        {:noreply, Conn.add_pid(conn, pid), {:continue, :upgrade}}
      end

      @impl GenServer
      def handle_continue(:upgrade, conn) do
        %{path: path, headers: headers, pid: pid} = conn

        log_debug("Connection succeeded, upgrading websocket to path #{path}.")

        stream =
          case headers do
            nil -> :gun.ws_upgrade(pid, path)
            headers -> :gun.ws_upgrade(pid, path, headers)
          end

        {:noreply, Conn.add_stream(conn, stream)}
      end

      @impl GenServer
      def handle_call({:push, message}, _from, conn) do
        %{pid: pid, state: state} = conn

        log_debug("Calling push with message #{inspect(message)}.")

        case handle_push(message, state) do
          {:push, frame, state} ->
            conn = Conn.update_state(conn, state)

            {:reply, :gun.ws_send(pid, frame), conn}

          {:ok, state} ->
            {:reply, :ok, Conn.update_state(conn, state)}

          {:close, frame, state} ->
            conn = Conn.update_state(conn, state)

            {:stop, :close, :gun.ws_send(pid, frame), conn}
        end
      end

      @impl GenServer
      def handle_info({:gun_ws, _, stream, frame}, conn) do
        log_debug("Received frame #{inspect(frame)} from socket #{inspect(stream)}.")

        %{pid: pid, state: state} = conn

        case handle_receive(frame, state) do
          {:push, frame, state} ->
            :ok = :gun.ws_send(pid, frame)

            {:noreply, Conn.update_state(conn, state)}

          {:ok, state} ->
            {:noreply, Conn.update_state(conn, state)}

          {:close, frame, state} ->
            :ok = :gun.ws_send(pid, frame)

            {:stop, :close, Conn.update_state(conn, state)}
        end
      end

      @impl GenServer
      def handle_info({:gun_upgrade, _client, _stream, protocols, headers}, conn) do
        log_debug("Connection upgraded successfully.")

        state = new_state(conn, protocols, headers)

        {:noreply, Conn.update_state(conn, state)}
      end

      @impl GenServer
      def handle_info({:gun_error, _client, {:badstate, reason}}, conn) do
        log_warn("Connection upgrade failed with reason #{inspect(reason)}.")

        {:stop, reason, conn}
      end

      @impl GenServer
      def handle_info({:DOWN, ref, _, _, reason}, %{monitor: ref} = conn) do
        %{stream: stream} = conn

        log_warn("Connection to socket #{stream} lost with reason #{inspect(reason)}.")

        {:stop, reason, conn}
      end

      @impl GenServer
      def handle_info({:EXIT, _, reason}, conn) do
        log_warn("Got EXIT message with reason #{inspect(reason)}.")

        {:stop, reason, conn}
      end

      @impl GenServer
      def terminate(reason, conn) do
        log_warn("Terminating process with reason #{inspect(reason)}.")

        %{pid: pid, monitor: monitor, stream: stream} = conn

        Process.demonitor(monitor)

        :gun.flush(stream)
        :gun.close(pid)

        conn
      end

      @impl Websocket
      def new_state(_, _, _), do: %{}

      @impl Websocket
      def handle_push(message, state) when is_binary(message),
        do: {:push, {:text, message}, state}

      @impl Websocket
      def handle_push({:close, reason}, state), do: {:close, {:close, reason}, state}

      @impl Websocket
      def handle_receive(frame, state), do: {:ok, state}

      defoverridable new_state: 3, handle_push: 2, handle_receive: 2

      case debug do
        true -> defp log_debug(message), do: Logger.debug(message)
        false -> defp log_debug(_), do: :noop
      end

      case debug do
        true -> defp log_warn(message), do: Logger.warn(message)
        false -> defp log_warn(_), do: :noop
      end
    end
  end
end