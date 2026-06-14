# Separate Deserialization Command

New-WhyLog returns YAML text as the default artifact, and deserialization is handled by a dedicated Read-WhyLog cmdlet. Read-WhyLog accepts both piped text and file path input and uses terminating errors on parse failure, because output-generation and parsing concerns should be separated cleanly for predictable composition.