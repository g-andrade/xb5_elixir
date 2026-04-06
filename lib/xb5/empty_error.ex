defmodule Xb5.EmptyError do
  @moduledoc """
  Raised when an operation requires a non-empty collection but an empty one was given.

  This exception is raised by functions such as `Xb5.Bag.first!/1`,
  `Xb5.Set.pop_last!/1`, `Xb5.Tree.pop_first!/1`, and similar bang variants across
  all three modules.
  """

  defexception message: "empty error"
end
