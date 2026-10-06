# Used by "mix format"
[
  import_deps: [:ash, :ash_postgres, :ash_double_entry, :ash_money, :ash_oban],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
