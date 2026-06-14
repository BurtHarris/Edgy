# Separate Edgey And WhyLog Modules

The repository will treat Edgey and WhyLog as distinct modules. Edgey remains the Edge-specific command-and-control tool, and WhyLog provides a reusable diagnostics DSL plus YAML reporting surface that Edgey consumes as an example integration, because separating domain operations from diagnostics infrastructure improves reuse and keeps boundaries clear.
