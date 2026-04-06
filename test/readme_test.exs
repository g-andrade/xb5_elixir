defmodule ReadmeTest do
  if Version.match?(System.version(), "~> 1.15") do
    use ExUnit.Case, async: true
    doctest_file("README.md")
  end
end
