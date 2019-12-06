defmodule ScenicSnake.Scene.Game do
  @moduledoc """
  The scene where the game of Snake happens!
  """

  use Scenic.Scene
  alias Scenic.Graph
  alias Scenic.ViewPort
  import Scenic.Primitives, only: [rrect: 3, text: 3]

  @compile {:inline, draw_tile: 4, move: 3}

  @empty_graph Graph.build(theme: :dark, font: :roboto, font_size: 36)

  @tile_size 40
  @tile_radius 8

  @frame_ms 32

  @snake_movement_delay 6
  @snake_starting_size 5
  @pellet_score 100

  @game_over_scene ScenicSnake.Scene.GameOver

  # Initial parameters for the game scene!
  def init(_arg, opts) do
    viewport = opts[:viewport]

    # Initializes the graph
    graph = @empty_graph

    # calculate the transform that centers the snake in the viewport
    {:ok, %ViewPort.Status{size: {vp_width, vp_height}}} = ViewPort.info(viewport)

    # how many tiles can the viewport hold in each dimension?
    vp_tile_width = trunc(vp_width / @tile_size)
    vp_tile_height = trunc(vp_height / @tile_size)

    # snake always starts centered
    snake_start_coords = {
      trunc(vp_tile_width / 2),
      trunc(vp_tile_height / 2)
    }

    # start a very simple animation timer
    {:ok, timer} = :timer.send_interval(@frame_ms, :frame)

    state = %{
      viewport: viewport,
      tile_width: vp_tile_width,
      tile_height: vp_tile_height,
      graph: graph,
      frame_count: 1,
      frame_timer: timer,
      score: 0,
      had_input: false,
      # Game objects
      objects: %{snake: %{body: [snake_start_coords],
                          size: @snake_starting_size,
                          direction: {1, 0}},

                 pellet: nil},
    } |> randomize_pellet()

    # draw snake and pellet
    graph
    |> draw_game_objects(state.objects)
    |> draw_score(state.score)
    |> push_graph()

    {:ok, state}
  end

  # A very simple frame counter. The game should run at roughly 30 fps, even though the snake
  # doesn't refresh every frame by default.
  def handle_info(:frame, %{frame_count: frame_count} = state) do
    state = if rem(frame_count, @snake_movement_delay) == 0 do
              move_snake(state)
            else
              state
            end

    state.graph |> draw_game_objects(state.objects) |> draw_score(state.score) |> push_graph()

    {:noreply, %{state | frame_count: frame_count + 1}}
  end

  def do_nothing(state) do
    state
  end

  # Keyboard controls
  def handle_input({:key, _}, _context, %{had_input: true} = state) do
    {:noreply, do_nothing(state)}
  end

  def handle_input({:key, {"left", :press, _}}, _context, state) do
    {:noreply, update_snake_direction(state, {-1, 0})}
  end

  def handle_input({:key, {"right", :press, _}}, _context, state) do
    {:noreply, update_snake_direction(state, {1, 0})}
  end

  def handle_input({:key, {"up", :press, _}}, _context, state) do
    {:noreply, update_snake_direction(state, {0, -1})}
  end

  def handle_input({:key, {"down", :press, _}}, _context, state) do
    {:noreply, update_snake_direction(state, {0, 1})}
  end

  def handle_input(_input, _context, state), do: {:noreply, state}

  # Change the snake's current direction.
  defp update_snake_direction(state, direction) do
    {old_x, old_y} = state.objects.snake.direction

    # Prevent going backwards and crashing instantly
    if (direction in [{-old_x, 0}, {0, -old_y}]) do
      state
    else
      put_in(state, [:objects, :snake, :direction], direction) |> put_in([:had_input], true)
    end
  end

  # Move the snake to its next position according to the direction. Also limits the size.
  defp move_snake(%{objects: %{snake: snake}} = state) do
    [head | _] = snake.body
    new_head_pos = move(state, head, snake.direction)

    new_body = Enum.take([new_head_pos | snake.body], snake.size)

    state
    |> maybe_eat_pellet(new_head_pos)
    |> maybe_die()
    |> put_in([:objects, :snake, :body], new_body)
    |> put_in([:had_input], false)
  end

  defp move(%{tile_width: w, tile_height: h}, {pos_x, pos_y}, {vec_x, vec_y}) do
    {rem(pos_x + vec_x + w, w), rem(pos_y + vec_y + h, h)}
  end

  # We're on top of a pellet! :)
  defp maybe_eat_pellet(state = %{objects: %{pellet: pellet_coords}}, snake_head_coords)
  when pellet_coords == snake_head_coords do
    state
    |> randomize_pellet()
    |> add_score(@pellet_score)
    |> grow_snake()
  end

  # No pellet in sight. :(
  defp maybe_eat_pellet(state, _), do: state

  # oh no
  defp maybe_die(state = %{viewport: vp, objects: %{snake: %{body: snake}}, score: score}) do
    # If ANY duplicates were removed, this means we overlapped at least once
    if length(Enum.uniq(snake)) < length(snake) do
      ViewPort.set_root(vp, {@game_over_scene, score})
    end
    state
  end

  # Place the pellet somewhere in the map. It should not be on top of the snake.
  defp randomize_pellet(state = %{tile_width: w, tile_height: h}) do
    pellet_coords = {
        Enum.random(0..(w-1)),
        Enum.random(0..(h-1)),
    }

    validate_pellet_coords(state, pellet_coords)
  end

  # Keep trying until we get a valid position
  defp validate_pellet_coords(state = %{objects: %{snake: %{body: snake}}}, coords) do
    if coords in snake, do: randomize_pellet(state),
                        else: put_in(state, [:objects, :pellet], coords)
  end

  # Increments the player's score.
  defp add_score(state, amount) do
    update_in(state, [:score], &(&1 + amount))
  end

  # Increments the snake size.
  defp grow_snake(state) do
    update_in(state, [:objects, :snake, :size], &(&1 + 1))
  end

  # Iterates over the object map, rendering each object
  defp draw_game_objects(graph, object_map) do
    Enum.reduce(object_map, graph, fn {object_type, object_data}, graph ->
        draw_object(graph, object_type, object_data)
    end)
  end

  # Snake's body is an array of coordinate pairs
  defp draw_object(graph, :snake, %{body: snake}) do
    Enum.reduce(snake, graph, fn {x, y}, graph ->
      draw_tile(graph, x, y, fill: :lime)
    end)
  end

  # Pellet is simply a coordinate pair
  defp draw_object(graph, :pellet, {pellet_x, pellet_y}) do
    draw_tile(graph, pellet_x, pellet_y, fill: :yellow, id: :pellet)
  end

  # Draw tiles as rounded rectangles to look nice
  defp draw_tile(graph, x, y, opts) do
    tile_opts = Keyword.merge([fill: :white, translate: {x * @tile_size, y * @tile_size}], opts)
    graph |> rrect({@tile_size, @tile_size, @tile_radius}, tile_opts)
  end

  # Draw the score HUD
  defp draw_score(graph, score) do
    graph
    |> text("Score: #{score}", fill: :black, font_blur: 2.0, translate: {@tile_size + 4,
                                                                             @tile_size + 4})
    |> text("Score: #{score}", fill: :white, translate: {@tile_size, @tile_size})
  end
end
