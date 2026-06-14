# WhyLog Module Surface

Edge diagnostics will be exposed as a module centered on New-WhyLog, not as a single command retrofit. The design separates an outer wrapper for stream interception/formatting from concise commands for tests, because this keeps day-to-day usage simple while preserving composability for test authoring.