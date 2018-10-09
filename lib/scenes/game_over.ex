defmodule ScenicSnake.Scene.GameOver do
  @moduledoc """
  This scene is shown when you lose the game.
  Nobody wants to see this scene.
  """

  use Scenic.Scene
  alias Scenic.Graph
  alias Scenic.ViewPort
  import Scenic.Primitives, only: [text: 3, group: 2, update_opts: 2]

  @text_opts [id: :gameover, fill: :white, text_align: :center]

  @graph Graph.build(font: :roboto, font_size: 36, clear_color: :black)
         |> group(fn(g) ->
          text(g, "Game Over!", @text_opts)
         end)

  @game_scene ScenicSnake.Scene.Game

  def init( score, opts ) do
    viewport = opts[:viewport]

    {:ok, %ViewPort.Status{size: {vp_width, vp_height}}} = ViewPort.info(viewport)

    position = {vp_width / 2, vp_height / 2}

    graph = @graph
          |> Graph.modify(:gameover, &update_opts(&1, translate: position))
          |> push_graph()

    state = %{
      graph: graph,
      viewport: opts[:viewport],
      on_cooldown: true,
      score: score
    }

    Process.send_after(self(), :end_cooldown, 2000)

    {:ok, state}
  end

  # Prevent player from hitting any key instantly, starting a new game
  def handle_info(:end_cooldown, state) do
    graph = state.graph
          |> Graph.modify(:gameover, &text(&1, "Game Over!\n"
                                            <> "You scored #{state.score}.\n"
                                            <> "Press any key to try again.",
                                           @text_opts))
          |> push_graph()

    {:noreply, %{state | on_cooldown: false, graph: graph}}
  end

  # If cooldown has passed, we can restart the game.
  def handle_input({:cursor_button, {_, :press, _, _}}, _context, %{on_cooldown: false} = state) do
    restart_game(state)
    {:noreply, state}
  end

  def handle_input({:key, _}, _context, %{on_cooldown: false} = state) do
    restart_game(state)
    {:noreply, state}
  end

  def handle_input(_input, _context, state), do: {:noreply, state}

  defp restart_game(%{viewport: vp}) do
    ViewPort.set_root(vp, {@game_scene, nil})
  end
end
