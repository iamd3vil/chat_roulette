defmodule ChatRoulette.ChatWorker do
  use GenServer
  require Logger

  @name_regex ~r/(?<name>.+)\n/


  def start_link(client) do
    GenServer.start_link(__MODULE__, client, [])
  end

  defp recv_name(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, "\n"} ->
        :gen_tcp.send(socket, "Eh? I don't think that's your name.. :(\r\n")
        recv_name(socket)
      {:ok, name} ->
        Logger.debug "In recv: name: #{name}"
        %{"name" => conv_name} = Regex.named_captures(@name_regex, name)
        {:ok, conv_name}
    end
  end

  def init(client) do
    send(self(), :after_join)
    {:ok, %{tcp_proc: client}}
  end

  def handle_info(:after_join, %{tcp_proc: client}) do
    :gen_tcp.send(client, "Hi. Welcome to Chat Roulette. We are going to connect you to a stranger. For now please enter your name:\r\n")
    {:ok, name} = recv_name(client)
    Logger.debug "CLient connected. Name: #{inspect name}"
    :pg2.create("available")
    connected_proc =
    case :pg2.get_members("available") do
      [] ->
        :pg2.join("available", self())
        :gen_tcp.send(client, "Hey #{name}. Waiting for someone to join\r\n")
        nil
      members ->
        member = members |> Enum.random
        GenServer.cast(member, {:connect, self()})
        :gen_tcp.send(client, "Hey #{name}. Found someone. Say hi\r\n")
        member
    end
    :inet.setopts(client, active: :once)
    {:noreply, %{connected_proc: connected_proc, tcp_proc: client, name: name}}
  end

  def handle_info({:tcp, socket, data}, %{connected_proc: nil, tcp_proc: client} = state) do
    :gen_tcp.send(client, data)
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "\n"}, %{connected_proc: pid, tcp_proc: _client, name: name} = state) do
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, line}, %{connected_proc: pid, tcp_proc: _client, name: name} = state) do
    Logger.debug "Received new message"
    GenServer.cast(pid, {:newmessage, "#{name}: #{line}"})
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end


  def handle_info({:tcp_closed, _}, state) do
    {:stop, :normal, state}
  end


  def terminate(:normal, %{connected_proc: pid, tcp_proc: _}) do
    GenServer.cast(pid, :disconnect)
    :ok
  end

  def handle_cast({:connect, pid}, %{tcp_proc: client, name: name}) do
    Logger.debug "Got connect request from pid"
    :pg2.leave("available", self())
    :pg2.create("connected")
    :pg2.join("connected", self())
    :gen_tcp.send(client, "Hey #{name}. Found someone say hi\r\n")
    {:noreply, %{tcp_proc: client, connected_proc: pid, name: name}}
  end

  def handle_cast(:disconnect, %{tcp_proc: client, name: name}) do
    :pg2.leave("connected", self())
    :pg2.join("available", self())
    :gen_tcp.send(client, "Your partner left. Waiting for someone else now\r\n")
    {:noreply, %{tcp_proc: client, connected_proc: nil, name: name}}
  end

  def handle_cast({:newmessage, msg}, %{tcp_proc: client, connected_proc: _pid} = state) do
    Logger.debug "Got new message from other pid"
    :gen_tcp.send(client, msg)
    {:noreply, state}
  end
end
